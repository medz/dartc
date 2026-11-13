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
    _registerLibraries(sdk, libraries);
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
        'double_patch.dart',
        'integers.dart',
        'array.dart',
        'growable_array.dart',
        'string_patch.dart',
        'record_patch.dart',
        'errors_patch.dart',
        'invocation_mirror_patch.dart',
        'function.dart',
        'type_patch.dart',
      };
      final parts = [
        for (final part in _parse(core).directives.whereType<PartDirective>())
          if (selected.remove(part.uri.stringValue))
            coreUri.resolve(part.uri.stringValue!).toFilePath(),
        patches('core')
            .singleWhere((path) => path.endsWith('/bool_patch.dart')),
        patches('core')
            .singleWhere((path) => path.endsWith('/bigint_patch.dart')),
        patches('core')
            .singleWhere((path) => path.endsWith('/integers_patch.dart')),
        patches('core')
            .singleWhere((path) => path.endsWith('/string_buffer_patch.dart')),
        patches('core')
            .singleWhere((path) => path.endsWith('/array_patch.dart')),
        patches('core').singleWhere((path) => path.endsWith('/map_patch.dart')),
      ];
      if (selected.isNotEmpty) {
        throw FormatException(
          'SDK implementation parts unavailable: $selected',
        );
      }
      _official.addAll([core, ...parts]);
      _apply(
        library('core'),
        [
          core,
          ...parts,
          '$runtime/core.dart',
          '$runtime/list.dart',
          '$runtime/string.dart',
          '$runtime/integer.dart',
          '$runtime/double.dart',
          '$runtime/record.dart',
        ],
        storageClasses: const {'_OneByteString', '_TwoByteString'},
      );
      final internal = patches('_internal')
          .singleWhere((path) => path.endsWith('/internal_patch.dart'));
      _official.add(internal);
      _apply(library('_internal'), [
        internal,
        '$runtime/class_id.dart',
        patches('_internal').singleWhere(
          (path) => path.endsWith('/check_valid_weak_target_patch.dart'),
        ),
        '$runtime/internal.dart',
        '$runtime/list_storage.dart',
        '$runtime/print.dart',
      ]);
      final async = patches('async')
          .singleWhere((path) => path.endsWith('/async_patch.dart'));
      _official.add(async);
      _apply(library('async'), [
        async,
        '$runtime/async.dart',
        '$runtime/timer.dart',
      ]);
      final typedData = patches('typed_data').single;
      _official.add(typedData);
      _apply(library('typed_data'), [typedData, '$runtime/typed_data.dart']);
      final collection = patches('collection')
          .singleWhere((path) => path.endsWith('/collection_patch.dart'));
      final hashes = patches('collection')
          .singleWhere((path) => path.endsWith('/hash_factories.dart'));
      _official.addAll([collection, hashes]);
      _apply(library('collection'), [
        collection,
        hashes,
        '$runtime/collection.dart',
      ]);
      _apply(
        library('_compact_hash'),
        ['$runtime/compact_hash.dart'],
        storageClasses: const {'_LinkedHashImmutableBase'},
      );
      final math = patches('math').single;
      _official.add(math);
      _apply(library('math'), [math]);
      final convert = patches('convert')
          .singleWhere((path) => path.endsWith('/convert_patch.dart'));
      _official.add(convert);
      _apply(library('convert'), [convert, '$runtime/convert.dart']);
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
        '_compact_hash',
        'convert',
        'math',
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

  void _registerLibraries(String sdk, Map<String, dynamic> libraries) {
    final path = '$sdk/lib/_internal/sdk_library_metadata/lib/libraries.dart';
    final declarations = _parse(path).declarations
        .whereType<TopLevelVariableDeclaration>()
        .expand((node) => node.variables.variables);
    final table =
        declarations
                .singleWhere((v) => v.name.lexeme == 'libraries')
                .initializer
            as SetOrMapLiteral;
    final existing = {
      for (final entry in table.elements.whereType<MapLiteralEntry>())
        (entry.key as StringLiteral).stringValue,
    };
    // Analyzer metadata omits backend-only libraries present in the VM manifest.
    final missing = [
      for (final MapEntry(key: name, value: info) in libraries.entries)
        if (name.startsWith('_') && !existing.contains(name))
          '${jsonEncode(name)}: const LibraryInfo(${jsonEncode(info['uri'])}, '
              'categories: "Server", implementation: true, documented: false, '
              'platforms: VM_PLATFORM),',
    ];
    if (missing.isEmpty) return;
    files.setOverlay(
      path,
      content: files
          .getFile(path)
          .readAsStringSync()
          .replaceRange(
            table.leftBracket.end,
            table.leftBracket.end,
            '\n${missing.join('\n')}\n',
          ),
      modificationStamp: 0,
    );
  }

  void _apply(
    String libraryPath,
    List<String> implementations, {
    Set<String>? classes,
    Set<String> storageClasses = const {},
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
    bool replaced(String path, CompilationUnitMember declaration) =>
        (_official.contains(path) || !implementations.contains(path)) &&
        declaration is ClassDeclaration &&
        storageClasses.contains(declaration.namePart.typeName.lexeme);
    for (final name in storageClasses) {
      final definitions = [
        for (final path in implementations.where((p) => !_official.contains(p)))
          ...units[path]!.declarations.whereType<ClassDeclaration>().where(
            (declaration) =>
                declaration.namePart.typeName.lexeme == name &&
                !_patched(declaration),
          ),
      ];
      if (!name.startsWith('_') || definitions.length != 1) {
        throw FormatException('SDK storage implementation unavailable: $name');
      }
    }
    final originals = <String, ClassDeclaration>{};
    final mixins = <String, MixinDeclaration>{};
    final members = <(String, (String?, String)), (String, ClassMember)>{};
    final functions = <(String, String?), (String, FunctionDeclaration)>{};
    for (final MapEntry(key: path, value: syntax) in units.entries) {
      for (final declaration in syntax.declarations) {
        if (replaced(path, declaration)) continue;
        final classMembers = switch (declaration) {
          ClassDeclaration() => (
            declaration.namePart.typeName.lexeme,
            declaration.body.members,
          ),
          MixinDeclaration() => (
            declaration.name.lexeme,
            declaration.body.members,
          ),
          _ => null,
        };
        if (classMembers case (final name, final declarations)) {
          for (final member in declarations.where((m) => !_patched(m))) {
            if (_memberKey(member) case final key?) {
              final identity = (name, key);
              if (members.containsKey(identity)) {
                throw FormatException(
                  'Duplicate SDK member: $path:${member.offset}',
                );
              }
              members[identity] = (path, member);
            }
          }
        }
        if (_patched(declaration)) continue;
        switch (declaration) {
          case ClassDeclaration():
            originals[declaration.namePart.typeName.lexeme] = declaration;
          case MixinDeclaration():
            mixins[declaration.name.lexeme] = declaration;
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
    final edits = <String, List<(int, int, String)>>{
      for (final MapEntry(key: path, value: syntax) in units.entries)
        if (!implementations.contains(path))
          path: [
            for (final declaration in syntax.declarations)
              if (replaced(path, declaration))
                (declaration.offset, declaration.end, ''),
          ],
    };
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
        final parent = originals[name];
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

    void allowImplementation(
      String path,
      AnnotatedNode declaration, {
      required AnnotatedNode implementation,
      bool externalBody = false,
    }) {
      final external = switch (declaration) {
        ConstructorDeclaration(:final externalKeyword) ||
        MethodDeclaration(:final externalKeyword) ||
        FunctionDeclaration(:final externalKeyword) => externalKeyword,
        _ => null,
      };
      if (external == null) {
        if (externalBody) {
          throw FormatException(
            'Cannot replace a Dart body with an external: $path',
          );
        }
        if (declaration is MethodDeclaration &&
            declaration.body is EmptyFunctionBody) {
          return;
        }
        final adaptation = implementation.metadata.any((annotation) {
          final arguments = annotation.arguments?.arguments;
          if (annotation.name.name != 'pragma' || arguments?.length != 2) {
            return false;
          }
          final name = arguments![0], reason = arguments[1];
          return name is StringLiteral &&
              name.stringValue == 'dartc:patch' &&
              reason is StringLiteral &&
              RegExp(r'^(storage|specification): .+')
                  .hasMatch(reason.stringValue ?? '');
        });
        if (!adaptation) {
          throw FormatException(
            'SDK Dart body requires an explicit storage or specification adaptation: $path:${declaration.offset}',
          );
        }
        final body = switch (declaration) {
          ConstructorDeclaration(:final body) ||
          MethodDeclaration(:final body) => body,
          FunctionDeclaration(:final functionExpression) =>
            functionExpression.body,
          _ => throw FormatException('Unsupported body'),
        };
        edit(path, body.offset, body.end, ';');
        return;
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
        if (replaced(path, declaration)) {
          edit(path, declaration.offset, declaration.end, '');
          continue;
        }
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
          case MixinDeclaration():
            final name = declaration.name.lexeme;
            final owner = mixins[name];
            if (owner == null ||
                !name.startsWith('_') ||
                declaration.onClause != null ||
                declaration.implementsClause != null) {
              throw FormatException('SDK mixin unavailable or changed: $path');
            }
            augment(
              path,
              declaration,
              owner.baseKeyword == null ? '' : 'base ',
            );
            for (final member in declaration.body.members) {
              if (!_patched(member)) {
                _checkPrivate(member, path);
                continue;
              }
              final (ownerPath, original) =
                  members[(name, _memberKey(member))] ??
                  (throw FormatException(
                    'SDK mixin member unavailable: $path',
                  ));
              augment(path, member);
              final isExternal =
                  member is MethodDeclaration && member.externalKeyword != null;
              allowImplementation(
                ownerPath,
                original,
                implementation: member,
                externalBody: isExternal,
              );
              if (!isExternal) {
                members[(name, _memberKey(member)!)] = (path, member);
              }
            }
          case ClassDeclaration():
            final owner =
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
              if (!owner.namePart.typeName.lexeme.startsWith('_') &&
                  !inheritsMember(owner, member)) {
                _checkPrivate(member, path);
              }
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
              final (ownerPath, target) =
                  members[(
                    declaration.namePart.typeName.lexeme,
                    _memberKey(member),
                  )] ??
                  (throw FormatException(
                    'SDK member unavailable: $path:${member.offset}',
                  ));
              final isExternal = switch (member) {
                ConstructorDeclaration(:final externalKeyword) ||
                MethodDeclaration(
                  :final externalKeyword,
                ) => externalKeyword != null,
                _ => false,
              };
              if (isExternal && _official.contains(path)) {
                // VM linkage metadata supplies no Dart body; retain the SDK declaration.
                edit(path, member.offset, member.end, '');
                continue;
              }
              augment(path, member);
              allowImplementation(
                ownerPath,
                target,
                implementation: member,
                externalBody: isExternal,
              );
              if (!isExternal) {
                members[(
                  declaration.namePart.typeName.lexeme,
                  _memberKey(member)!,
                )] = (
                  path,
                  member,
                );
              }
              if (_official.contains(path)) {
                final parameters = switch (member) {
                  ConstructorDeclaration(:final parameters) => parameters,
                  MethodDeclaration(:final parameters) => parameters,
                  _ => null,
                };
                if (parameters == null) continue;
                final targetParameters = switch (target) {
                  ConstructorDeclaration(:final parameters) => parameters,
                  MethodDeclaration(:final parameters) => parameters,
                  _ => null,
                };
                final positional =
                    targetParameters?.parameters
                        .where((p) => p.isPositional)
                        .toList() ??
                    <FormalParameter>[];
                // VM patches may rename positional parameters, which callers bind by position.
                for (final (i, p)
                    in parameters.parameters
                        .where((p) => p.isPositional)
                        .indexed) {
                  if (i >= positional.length) break;
                  final name = p.name, originalName = positional[i].name;
                  final body = switch (member) {
                    ConstructorDeclaration(:final body) ||
                    MethodDeclaration(:final body) => body,
                    _ => null,
                  };
                  final implementationType = p is RegularFormalParameter
                      ? p.type
                      : null;
                  final originalParameter = positional[i];
                  final originalType =
                      originalParameter is RegularFormalParameter
                      ? originalParameter.type
                      : null;
                  if (name != null &&
                      originalName != null &&
                      body is BlockFunctionBody &&
                      implementationType is NamedType &&
                      originalType is NamedType &&
                      implementationType.name.lexeme ==
                          originalType.name.lexeme &&
                      implementationType.typeArguments == null &&
                      (originalType.typeArguments?.arguments.any(
                            (type) => type.toSource() != 'dynamic',
                          ) ??
                          false)) {
                    var argument = '_sdkArgument$i';
                    while (member.toSource().contains(argument)) {
                      argument += '_';
                    }
                    // Retain the public type and the VM body's raw implementation view.
                    edit(
                      path,
                      implementationType.offset,
                      implementationType.end,
                      originalType.toSource(),
                    );
                    edit(path, name.offset, name.end, argument);
                    edit(
                      ownerPath,
                      originalName.offset,
                      originalName.end,
                      argument,
                    );
                    edit(
                      path,
                      body.block.leftBracket.end,
                      body.block.leftBracket.end,
                      '\nfinal ${implementationType.toSource()} ${name.lexeme} = $argument;\n',
                    );
                    continue;
                  }
                  if (name != null &&
                      originalName != null &&
                      name.lexeme != '_' &&
                      name.lexeme != originalName.lexeme) {
                    edit(
                      ownerPath,
                      originalName.offset,
                      originalName.end,
                      name.lexeme,
                    );
                  }
                }
                final extras =
                    member is MethodDeclaration && target is MethodDeclaration
                    ? parameters.parameters
                          .where(
                            (p) =>
                                p.isNamed &&
                                !target.parameters!.parameters.any(
                                  (t) =>
                                      t.isNamed &&
                                      t.name?.lexeme == p.name?.lexeme,
                                ),
                          )
                          .toSet()
                    : <FormalParameter>{};
                if (extras.isNotEmpty) {
                  if (member is! MethodDeclaration ||
                      member.body is! BlockFunctionBody ||
                      extras.any(
                        (p) =>
                            p is! RegularFormalParameter ||
                            !p.isOptionalNamed ||
                            p.defaultClause != null,
                      )) {
                    throw FormatException(
                      'Unsupported SDK implementation parameters: $path:${member.offset}',
                    );
                  }
                  // Implementation-only optional parameters are never supplied by the public API.
                  final locals = [
                    for (final p in extras)
                      '${p.type?.toSource() ?? 'dynamic'}${p.functionTypedSuffix == null ? '' : ' Function${p.functionTypedSuffix!.toSource()}'} ${p.name!.lexeme} = null;',
                  ];
                  final body = member.body as BlockFunctionBody;
                  edit(
                    path,
                    body.block.leftBracket.end,
                    body.block.leftBracket.end,
                    '\n${locals.join('\n')}',
                  );
                  String spelling(FormalParameter p) => files
                      .getFile(path)
                      .readAsStringSync()
                      .substring(p.offset, p.defaultClause?.offset ?? p.end);
                  final kept = parameters.parameters.where(
                    (p) => !extras.contains(p),
                  );
                  final optional = kept
                      .where((p) => !p.isRequiredPositional)
                      .toList();
                  final parts = [
                    ...kept.where((p) => p.isRequiredPositional).map(spelling),
                    if (optional.isNotEmpty)
                      '${optional.first.isNamed ? '{' : '['}${optional.map(spelling).join(', ')}${optional.first.isNamed ? '}' : ']'}',
                  ];
                  edit(
                    path,
                    parameters.offset,
                    parameters.end,
                    '(${parts.join(', ')})',
                  );
                  continue;
                }
                // The public SDK declaration owns defaults repeated by VM patches.
                for (final parameter in parameters.parameters) {
                  if (parameter.defaultClause case final clause?) {
                    edit(path, clause.offset, clause.end, '');
                  }
                }
              }
            }
          case FunctionDeclaration():
            if (declaration.externalKeyword != null &&
                _official.contains(path)) {
              edit(path, declaration.offset, declaration.end, '');
              continue;
            }
            final (ownerPath, owner) =
                functions[(
                  declaration.name.lexeme,
                  declaration.propertyKeyword?.lexeme,
                )] ??
                (throw FormatException('SDK function unavailable: $path'));
            if (_official.contains(path) && owner.externalKeyword == null) {
              // Keep an existing Dart body instead of a VM-only specialization.
              edit(path, declaration.offset, declaration.end, '');
              continue;
            }
            augment(path, declaration);
            allowImplementation(
              ownerPath,
              owner,
              implementation: declaration,
              externalBody: declaration.externalKeyword != null,
            );
            if (declaration.externalKeyword == null) {
              functions[(
                declaration.name.lexeme,
                declaration.propertyKeyword?.lexeme,
              )] = (
                path,
                declaration,
              );
            }
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
    propertyKeyword?.lexeme ??
        (member.isOperator && member.parameters!.parameters.isEmpty
            ? 'unary'
            : 'method'),
  ),
  _ => null,
};

void _checkPrivate(AnnotatedNode node, String path) {
  final names = switch (node) {
    ClassDeclaration(:final namePart) ||
    EnumDeclaration(:final namePart) => [namePart.typeName.lexeme],
    FunctionDeclaration(:final name) ||
    MixinDeclaration(:final name) ||
    TypeAlias(:final name) ||
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
