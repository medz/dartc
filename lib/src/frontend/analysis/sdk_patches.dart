import 'dart:convert';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/file_system/overlay_file_system.dart';

/// Connects target implementations to SDK declarations through augmentation.
final class SdkPatches(final OverlayResourceProvider files) {
  final origins = <Uri, Uri>{};
  final _official = <String>{};
  CompilationUnit _parse(String path) => parseString(
    content: files.getFile(path).readAsStringSync(),
    path: path,
    featureSet: FeatureSet.latestLanguageVersion(),
  ).unit;

  void install(String sdk, String? runtime) {
    final root = files.getFile('$sdk/lib/libraries.json').toUri();
    final manifest = jsonDecode(
      files.getFile('$sdk/lib/libraries.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final libraries =
        manifest['vm_common']['libraries'] as Map<String, dynamic>;
    String library(String name) =>
        root.resolve(libraries[name]['uri']).toFilePath();
    List<String> patches(String name) => switch (libraries[name]['patches']) {
      String path => [root.resolve(path).toFilePath()],
      List paths => [
        for (final String path in paths) root.resolve(path).toFilePath(),
      ],
      _ => const [],
    };
    final ffi = patches('ffi')
        .singleWhere((path) => path.endsWith('/ffi_patch.dart'));
    _official.add(ffi);
    _apply(
      library('ffi'),
      [ffi, if (runtime != null) '$runtime/ffi.dart'],
      classes: const {'_ArraySize'},
    );
    if (runtime != null) {
      final core = patches('core')
          .singleWhere((path) => path.endsWith('/core_patch.dart'));
      final coreUri = files.getFile(core).toUri();
      final selected = {
        'expando_patch.dart',
        'weak_property.dart',
        'double.dart',
        'integers.dart',
        'string_patch.dart',
      };
      final parts = [
        for (final part in _parse(core).directives.whereType<PartDirective>())
          if (selected.remove(part.uri.stringValue))
            coreUri.resolve(part.uri.stringValue!).toFilePath(),
        patches('core')
            .singleWhere((path) => path.endsWith('/bool_patch.dart')),
        patches('core')
            .singleWhere((path) => path.endsWith('/bigint_patch.dart')),
      ];
      if (selected.isNotEmpty) {
        throw FormatException(
          'SDK implementation parts unavailable: $selected',
        );
      }
      _official.addAll([core, ...parts]);
      _apply(library('core'), [
        core,
        ...parts,
        '$runtime/core.dart',
        '$runtime/list.dart',
        '$runtime/string.dart',
        '$runtime/integer.dart',
        '$runtime/double.dart',
      ]);
      final internal = patches('_internal')
          .singleWhere((path) => path.endsWith('/internal_patch.dart'));
      _official.add(internal);
      _apply(library('_internal'), [
        internal,
        files
            .getFile(internal)
            .toUri()
            .resolve('class_id_fasta.dart')
            .toFilePath(),
        patches('_internal').singleWhere(
          (path) => path.endsWith('/check_valid_weak_target_patch.dart'),
        ),
        '$runtime/internal.dart',
        '$runtime/print.dart',
      ]);
      _apply(library('async'), ['$runtime/async.dart', '$runtime/timer.dart']);
      _apply(library('typed_data'), ['$runtime/typed_data.dart']);
      final collection = patches('collection')
          .singleWhere((path) => path.endsWith('/collection_patch.dart'));
      _official.add(collection);
      _apply(library('collection'), [collection, '$runtime/collection.dart']);
      _apply(library('_vm'), ['$runtime/vm.dart']);
    }

    final experimentsPath = '$sdk/lib/_internal/allowed_experiments.json';
    final experiments = jsonDecode(
      files.getFile(experimentsPath).readAsStringSync(),
    ) as Map<String, dynamic>;
    experiments['experimentSets']['dartc'] = ['augmentations'];
    final sdkLibraries =
        experiments['sdk']['libraries'] as Map<String, dynamic>? ?? {};
    for (final name in [
      'ffi',
      if (runtime != null) ...[
        'core',
        '_internal',
        'async',
        'collection',
        'typed_data',
        '_vm',
      ],
    ]) {
      sdkLibraries[name] = {'experimentSet': 'dartc'};
    }
    experiments['sdk']['libraries'] = sdkLibraries;
    files.setOverlay(
      experimentsPath,
      content: jsonEncode(experiments),
      modificationStamp: 0,
    );
  }

  void _apply(
    String libraryPath,
    List<String> implementations, {
    Set<String>? classes,
  }) {
    final library = files.getFile(libraryPath);
    final libraryUri = library.toUri();
    final unit = _parse(libraryPath);
    final libraryName = unit.directives
        .whereType<LibraryDirective>()
        .single
        .name!
        .toSource()
        .substring('dart.'.length);
    final ownerUri = Uri.parse('dart:$libraryName');
    final views = {
      for (final path in implementations)
        path:
            '_implementations/${files.pathContext.split(path).skip(1).join('/')}',
    };
    final original = library.readAsStringSync();
    final paths = [
      libraryPath,
      for (final part in unit.directives.whereType<PartDirective>())
        libraryUri.resolve(part.uri.stringValue!).toFilePath(),
      ...implementations,
    ];
    final units = {for (final path in paths) path: _parse(path)};
    final replacements = {
      for (final path in implementations.where((p) => !_official.contains(p)))
        for (final declaration
            in units[path]!.declarations.whereType<ClassDeclaration>())
          if (_patched(declaration))
            for (final member in declaration.body.members.where(_patched))
              if (switch (member) {
                ConstructorDeclaration(:final externalKeyword) ||
                MethodDeclaration(
                  :final externalKeyword,
                ) => externalKeyword == null,
                _ => false,
              })
                (declaration.namePart.typeName.lexeme, _memberKey(member)),
    };
    final originals = <String, (String, ClassDeclaration)>{};
    final functions = <(String, String?), (String, FunctionDeclaration)>{};
    for (final MapEntry(key: path, value: syntax) in units.entries) {
      for (final declaration in syntax.declarations) {
        if (_patched(declaration)) continue;
        switch (declaration) {
          case ClassDeclaration():
            originals[declaration.namePart.typeName.lexeme] = (
              path,
              declaration,
            );
          case FunctionDeclaration():
            functions[(
              declaration.name.lexeme,
              declaration.propertyKeyword?.lexeme,
            )] = (
              path,
              declaration,
            );
        }
      }
    }
    final edits = <String, List<(int, int, String)>>{};
    bool inheritsMember(ClassDeclaration owner, ClassMember member) {
      if (member is! MethodDeclaration || member.isStatic) return false;
      Iterable<String> parents(ClassDeclaration declaration) => [
        declaration.extendsClause?.superclass.name.lexeme ?? 'Object',
        for (final type
            in declaration.withClause?.mixinTypes ?? const <NamedType>[])
          type.name.lexeme,
        for (final type
            in declaration.implementsClause?.interfaces ?? const <NamedType>[])
          type.name.lexeme,
      ];
      final pending = parents(owner).toList();
      final visited = {owner.namePart.typeName.lexeme};
      for (var i = 0; i < pending.length; i++) {
        final name = pending[i];
        if (!visited.add(name)) continue;
        final parent = originals[name]?.$2;
        if (parent == null) continue;
        if (parent.body.members.any(
          (m) =>
              m is MethodDeclaration &&
              !m.isStatic &&
              _memberKey(m) == _memberKey(member),
        )) {
          return true;
        }
        pending.addAll(parents(parent));
      }
      return false;
    }

    void edit(String path, int start, int end, String text) =>
        edits.putIfAbsent(path, () => []).add((start, end, text));
    void augment(
      String path,
      AnnotatedNode declaration, [
      String modifiers = '',
    ]) {
      for (final annotation in declaration.metadata.where(
        (a) => a.name.name == 'patch',
      )) {
        edit(path, annotation.offset, annotation.end, '');
      }
      final start = declaration.firstTokenAfterCommentAndMetadata.offset;
      edit(path, start, start, 'augment $modifiers');
    }

    void allowImplementation(String path, AnnotatedNode declaration) {
      final external = switch (declaration) {
        ConstructorDeclaration(:final externalKeyword) ||
        MethodDeclaration(:final externalKeyword) ||
        FunctionDeclaration(:final externalKeyword) => externalKeyword,
        _ => null,
      };
      if (external == null) {
        if (declaration is MethodDeclaration &&
            declaration.body is EmptyFunctionBody) {
          return;
        }
        throw FormatException(
          'Expected external SDK declaration: $path:${declaration.offset}',
        );
      }
      edit(path, external.offset, external.end, ' ' * external.length);
    }

    final imports = <String>{};
    for (final path in implementations) {
      final source = files.getFile(path).readAsStringSync();
      final syntax = units[path] ?? _parse(path);
      for (final directive in syntax.directives.whereType<ImportDirective>()) {
        imports.add(
          source
              .substring(directive.offset, directive.end)
              .replaceRange(
                directive.uri.offset - directive.offset,
                directive.uri.end - directive.offset,
                "'${files.getFile(path).toUri().resolve(directive.uri.stringValue!)}'",
              ),
        );
      }
    }
    for (final path in implementations) {
      final syntax = units[path]!;
      for (final directive in syntax.directives) {
        edit(path, directive.offset, directive.end, '');
      }
      edit(path, 0, 0, "part of '$ownerUri';\n");
      for (final declaration in syntax.declarations) {
        if (classes != null &&
            _official.contains(path) &&
            (declaration is! ClassDeclaration ||
                !classes.contains(declaration.namePart.typeName.lexeme))) {
          edit(path, declaration.offset, declaration.end, '');
          continue;
        }
        if (!_patched(declaration)) {
          if (!libraryName.startsWith('_')) _checkPrivate(declaration, path);
          continue;
        }
        switch (declaration) {
          case ClassDeclaration():
            final (ownerPath, owner) =
                originals[declaration.namePart.typeName.lexeme] ??
                (throw FormatException('SDK class unavailable: $path'));
            final interfaces = declaration.implementsClause;
            final repeatsInterfaces =
                _official.contains(path) &&
                interfaces != null &&
                interfaces.toSource() == owner.implementsClause?.toSource();
            if (declaration.extendsClause != null ||
                declaration.withClause != null ||
                interfaces != null &&
                    !repeatsInterfaces &&
                    !declaration.namePart.typeName.lexeme.startsWith('_')) {
              throw FormatException(
                'SDK implementation changes class hierarchy: $path',
              );
            }
            if (repeatsInterfaces) {
              edit(path, interfaces.offset, interfaces.end, '');
            }
            for (final member in declaration.body.members.where(
              (m) => !_patched(m),
            )) {
              if (!inheritsMember(owner, member)) _checkPrivate(member, path);
            }
            final modifiers = [
              if (declaration.abstractKeyword == null) owner.abstractKeyword,
              if (declaration.baseKeyword == null) owner.baseKeyword,
              if (declaration.finalKeyword == null) owner.finalKeyword,
              if (declaration.interfaceKeyword == null) owner.interfaceKeyword,
              if (declaration.sealedKeyword == null) owner.sealedKeyword,
              if (declaration.mixinKeyword == null) owner.mixinKeyword,
            ].nonNulls;
            augment(
              path,
              declaration,
              modifiers.map((token) => '${token.lexeme} ').join(),
            );
            for (final member in declaration.body.members.where(_patched)) {
              // Target bodies replace VM-specific bodies while retaining the SDK contract.
              if (_official.contains(path) &&
                  replacements.contains((
                    declaration.namePart.typeName.lexeme,
                    _memberKey(member),
                  ))) {
                edit(path, member.offset, member.end, '');
                continue;
              }
              final target = owner.body.members
                  .where(
                    (candidate) => _memberKey(candidate) == _memberKey(member),
                  )
                  .singleOrNull;
              if (target == null) {
                throw FormatException(
                  'SDK member unavailable: $path:${member.offset}',
                );
              }
              final isExternal = switch (member) {
                ConstructorDeclaration(:final externalKeyword) ||
                MethodDeclaration(
                  :final externalKeyword,
                ) => externalKeyword != null,
                _ => false,
              };
              if (isExternal) {
                // VM linkage metadata supplies no Dart body; retain the SDK declaration.
                edit(path, member.offset, member.end, '');
                continue;
              }
              augment(path, member);
              allowImplementation(ownerPath, target);
              if (_official.contains(path)) {
                final parameters = switch (member) {
                  ConstructorDeclaration(:final parameters) =>
                    parameters.parameters,
                  MethodDeclaration(:final parameters) =>
                    parameters?.parameters ?? const <FormalParameter>[],
                  _ => const <FormalParameter>[],
                };
                // The public SDK declaration owns defaults repeated by VM patches.
                for (final parameter in parameters) {
                  if (parameter.defaultClause case final clause?) {
                    edit(path, clause.offset, clause.end, '');
                  }
                }
              }
            }
          case FunctionDeclaration():
            if (declaration.externalKeyword != null) {
              edit(path, declaration.offset, declaration.end, '');
              continue;
            }
            augment(path, declaration);
            final (ownerPath, owner) =
                functions[(
                  declaration.name.lexeme,
                  declaration.propertyKeyword?.lexeme,
                )] ??
                (throw FormatException('SDK function unavailable: $path'));
            allowImplementation(ownerPath, owner);
          default:
            throw FormatException('Unsupported SDK augmentation: $path');
        }
      }
    }
    for (final MapEntry(key: path, value: changes) in edits.entries) {
      var content = files.getFile(path).readAsStringSync();
      changes.sort(
        (a, b) => a.$1 == b.$1 ? b.$2.compareTo(a.$2) : b.$1.compareTo(a.$1),
      );
      for (final (start, end, replacement) in changes) {
        content = content.replaceRange(start, end, replacement);
      }
      final destination = views[path];
      files.setOverlay(
        destination == null
            ? path
            : files.pathContext.join(library.parent.path, destination),
        content: content,
        modificationStamp: 0,
      );
    }
    final parts = unit.directives.whereType<PartDirective>();
    final insert = parts.firstOrNull?.offset ?? unit.directives.last.end;
    final end = parts.lastOrNull?.end ?? insert;
    var content = edits.containsKey(libraryPath)
        ? files.getFile(libraryPath).readAsStringSync()
        : original;
    content = content.replaceRange(
      end,
      end,
      "\n${views.values.map((path) => "part '$path';").join('\n')}\n",
    );
    content = content.replaceRange(insert, insert, "${imports.join('\n')}\n");
    files.setOverlay(libraryPath, content: content, modificationStamp: 0);
    for (final MapEntry(key: path, value: view) in views.entries) {
      origins[Uri.parse('$ownerUri/$view')] = files.getFile(path).toUri();
    }
  }
}

bool _patched(AnnotatedNode node) =>
    node.metadata.any((annotation) => annotation.name.name == 'patch');

(String?, String)? _memberKey(ClassMember member) => switch (member) {
  ConstructorDeclaration(:final name) => (name?.lexeme, 'constructor'),
  MethodDeclaration(:final name, :final propertyKeyword) => (
    name.lexeme,
    propertyKeyword?.lexeme ?? 'method',
  ),
  _ => null,
};

void _checkPrivate(AnnotatedNode node, String path) {
  final names = switch (node) {
    ClassDeclaration(:final namePart) ||
    EnumDeclaration(:final namePart) => [namePart.typeName.lexeme],
    FunctionDeclaration(:final name) ||
    MethodDeclaration(:final name) => [name.lexeme],
    TopLevelVariableDeclaration(:final variables) ||
    FieldDeclaration(
      fields: final variables,
    ) => variables.variables.map((variable) => variable.name.lexeme),
    ConstructorDeclaration(:final name) => [name?.lexeme ?? 'new'],
    _ => throw FormatException(
      'Unsupported SDK declaration: $path:${node.offset}',
    ),
  };
  if (names.any((name) => !name.startsWith('_'))) {
    throw FormatException(
      'SDK implementation adds public declarations: $path:${node.offset}',
    );
  }
}
