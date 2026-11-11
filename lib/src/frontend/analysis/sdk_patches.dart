import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/file_system/overlay_file_system.dart';

/// Installs checked factory bodies and private declarations into an SDK library.
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
    final classes = {
      for (final declaration in parse(
        partSource,
        partPath,
      ).declarations.whereType<ClassDeclaration>())
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
      if (declaration is! ClassDeclaration) {
        throw FormatException('Expected a factory patch class: $patchPath');
      }
      final match = classes[declaration.namePart.typeName.lexeme];
      if (match == null ||
          match.namePart.typeParameters?.toSource() !=
              declaration.namePart.typeParameters?.toSource()) {
        throw FormatException('SDK patch class does not match: $patchPath');
      }
      for (final member in declaration.body.members) {
        if (member is! ConstructorDeclaration ||
            member.factoryKeyword == null) {
          throw FormatException('Expected a factory patch: $patchPath');
        }
        final target = match.body.members
            .whereType<ConstructorDeclaration>()
            .where((ctor) => ctor.name?.lexeme == member.name?.lexeme)
            .singleOrNull;
        if (target == null ||
            target.externalKeyword == null ||
            target.factoryKeyword == null ||
            target.parameters.toSource() != member.parameters.toSource() ||
            member.body is EmptyFunctionBody) {
          throw FormatException('SDK factory patch does not match: $patchPath');
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
