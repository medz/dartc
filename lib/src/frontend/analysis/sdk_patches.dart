import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/file_system/overlay_file_system.dart';

/// Completes SDK external members with Dart bodies and private storage.
final class SdkPatches(final OverlayResourceProvider files) {
  void apply(String libraryPath, String partPath, String patchPath) {
    final library = files.getFile(libraryPath);
    final part = files.getFile(partPath);
    final patch = files.getFile(patchPath);
    final original = library.readAsStringSync();
    final source = patch.readAsStringSync();
    CompilationUnit parse(String content, String path) => parseString(
      content: content,
      path: path,
      featureSet: FeatureSet.latestLanguageVersion(),
    ).unit;
    final unit = parse(original, libraryPath);
    final partSource = part.readAsStringSync();
    final additions = parse(source, patchPath);
    final edits = <(int, int, String)>[];
    final declarations = parse(partSource, partPath).declarations;
    final classes = {
      for (final declaration in declarations.whereType<ClassDeclaration>())
        declaration.namePart.typeName.lexeme: declaration,
    };
    final helpers = <String>[];
    for (final declaration in additions.declarations) {
      final patched = declaration.metadata.any(
        (annotation) => annotation.name.name == 'patch',
      );
      if (!patched) {
        helpers.add(source.substring(declaration.offset, declaration.end));
        continue;
      }
      if (declaration is FunctionDeclaration) {
        final target = declarations
            .whereType<FunctionDeclaration>()
            .where(
              (d) =>
                  d.name.lexeme == declaration.name.lexeme &&
                  d.propertyKeyword?.lexeme ==
                      declaration.propertyKeyword?.lexeme,
            )
            .singleOrNull;
        if (target == null ||
            target.externalKeyword == null ||
            target.returnType?.toSource() !=
                declaration.returnType?.toSource() ||
            target.functionExpression.parameters?.toSource() !=
                declaration.functionExpression.parameters?.toSource() ||
            target.functionExpression.typeParameters?.toSource() !=
                declaration.functionExpression.typeParameters?.toSource() ||
            declaration.functionExpression.body is EmptyFunctionBody) {
          throw FormatException(
            'SDK function patch does not match: $patchPath',
          );
        }
        edits.add((
          target.externalKeyword!.offset,
          target.externalKeyword!.end,
          '',
        ));
        edits.add((
          target.functionExpression.body.offset,
          target.functionExpression.body.end,
          source.substring(
            declaration.functionExpression.body.offset,
            declaration.end,
          ),
        ));
        continue;
      }
      if (declaration is! ClassDeclaration) {
        throw FormatException('Expected a patch class: $patchPath');
      }
      final match = classes[declaration.namePart.typeName.lexeme];
      if (match == null ||
          match.namePart.typeParameters?.toSource() !=
              declaration.namePart.typeParameters?.toSource()) {
        throw FormatException('SDK patch class does not match: $patchPath');
      }
      final privateMembers = <String>[];
      for (final member in declaration.body.members) {
        if (member is FieldDeclaration &&
                member.fields.variables.every(
                  (field) => field.name.lexeme.startsWith('_'),
                ) ||
            member is MethodDeclaration &&
                member.name.lexeme.startsWith('_') &&
                !match.body.members.whereType<MethodDeclaration>().any(
                  (method) => method.name.lexeme == member.name.lexeme,
                )) {
          privateMembers.add(source.substring(member.offset, member.end));
          continue;
        }
        switch (member) {
          case ConstructorDeclaration():
            final target = match.body.members
                .whereType<ConstructorDeclaration>()
                .where((ctor) => ctor.name?.lexeme == member.name?.lexeme)
                .singleOrNull;
            if (target == null ||
                target.externalKeyword == null ||
                (target.factoryKeyword == null) !=
                    (member.factoryKeyword == null) ||
                target.parameters.toSource() != member.parameters.toSource() ||
                member.body is EmptyFunctionBody &&
                    member.initializers.isEmpty) {
              throw FormatException(
                'SDK constructor patch does not match: $patchPath',
              );
            }
            edits.add((
              target.externalKeyword!.offset,
              target.externalKeyword!.end,
              '',
            ));
            edits.add((
              target.parameters.end,
              target.end,
              source.substring(member.parameters.end, member.end),
            ));
          case MethodDeclaration():
            final target = match.body.members
                .whereType<MethodDeclaration>()
                .where(
                  (method) =>
                      method.name.lexeme == member.name.lexeme &&
                      method.propertyKeyword?.lexeme ==
                          member.propertyKeyword?.lexeme,
                )
                .singleOrNull;
            if (target == null ||
                target.externalKeyword == null ||
                target.isStatic != member.isStatic ||
                target.returnType?.toSource() !=
                    member.returnType?.toSource() ||
                target.typeParameters?.toSource() !=
                    member.typeParameters?.toSource() ||
                target.parameters?.toSource() !=
                    member.parameters?.toSource() ||
                member.body is EmptyFunctionBody) {
              throw FormatException(
                'SDK method patch does not match: $patchPath',
              );
            }
            edits.add((
              target.externalKeyword!.offset,
              target.externalKeyword!.end,
              '',
            ));
            edits.add((
              target.body.offset,
              target.body.end,
              source.substring(member.body.offset, member.body.end),
            ));
          default:
            throw FormatException(
              'Expected an external member or private storage: $patchPath',
            );
        }
      }
      if (privateMembers.isNotEmpty) {
        final end = match.body.endToken.offset;
        edits.add((end, end, privateMembers.join('\n')));
      }
    }
    var content = partSource;
    edits.sort((a, b) => b.$1.compareTo(a.$1));
    for (final (start, end, replacement) in edits) {
      content = content.replaceRange(start, end, replacement);
    }
    files.setOverlay(partPath, content: content, modificationStamp: 0);
    final imports = additions.directives.whereType<ImportDirective>().map((d) {
      final text = source.substring(d.offset, d.end);
      return text.replaceRange(
        d.uri.offset - d.offset,
        d.uri.end - d.offset,
        "'${patch.toUri().resolve(d.uri.stringValue!)}'",
      );
    });
    final insert = unit.directives.whereType<PartDirective>().first.offset;
    final current = library.readAsStringSync();
    files.setOverlay(
      libraryPath,
      content: current.replaceRange(
        insert,
        insert,
        "${imports.join('\n')}\npart '${patch.toUri()}';\n",
      ),
      modificationStamp: 0,
    );
    files.setOverlay(
      patchPath,
      content: "part of '${library.toUri()}';\n${helpers.join('\n')}",
      modificationStamp: 0,
    );
  }
}
