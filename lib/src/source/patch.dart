import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';

/// Applies [patches] to a library whose file [main] and parts are [files], as
/// texts by their paths. Returns the library's new files.
///
/// Declarations and members with the annotation `@patch` replace those of the
/// same name, or add their members and annotations to them. All others are
/// added to the library, in parts whose names start with [added].
///
/// Patches can be of what other patches add.
Map<String, String> patchLibrary(
  Map<String, String> files,
  String main,
  Map<String, String> patches, {
  required String added,
}) {
  var current = files, pending = patches;
  for (var round = 0; pending.isNotEmpty; round++) {
    final patcher = _Patcher(current);
    final units = {
      for (final MapEntry(key: path, value: text) in pending.entries)
        path: _parse(path, text),
    };
    final ready = {
      for (final MapEntry(key: path, value: unit) in units.entries)
        if (patcher.missing(unit) == null) path,
    };
    if (ready.isEmpty) {
      final path = pending.keys.first;
      final missing = patcher.missing(units[path]!);
      throw FormatException('$path patches $missing, which there is not.');
    }
    for (final path in ready) {
      patcher.apply(units[path]!, pending[path]!);
    }
    current = patcher.result(main, '$added$round.dart');
    pending = {
      for (final MapEntry(key: path, value: text) in pending.entries)
        if (!ready.contains(path)) path: text,
    };
  }
  return current;
}

CompilationUnit _parse(String path, String text) => parseString(
  content: text,
  path: '/$path',
  featureSet: FeatureSet.latestLanguageVersion(),
  throwIfDiagnostics: false,
).unit;

final class _Patcher(final Map<String, String> _files) {
  final _declarations = <String, (String, CompilationUnitMember)>{};

  /// The members of each declaration.
  final _members = <String, Map<String, (String, ClassMember)>>{};
  final _edits = <String, List<(int, int, String)>>{};
  final _units = <String, CompilationUnit>{};
  final _imports = <String>[], _added = <String>[];

  this {
    _files.forEach((path, text) {
      final unit = _units[path] = _parse(path, text);
      for (final declaration in unit.declarations) {
        for (final key in _keysOf(declaration)) {
          _declarations[key] = (path, declaration);
          _members[key] = {
            for (final member in _membersOf(declaration))
              for (final key in _memberKeys(member)) key: (path, member),
          };
        }
      }
    });
  }

  /// What [unit] patches that there is not, if anything.
  String? missing(CompilationUnit unit) {
    for (final declaration in unit.declarations.where(_isPatch)) {
      for (final key in _keysOf(declaration)) {
        if (!_declarations.containsKey(key)) return key;
        for (final member in _membersOf(declaration).where(_isPatch)) {
          final keys = _memberKeys(member);
          if (!keys.any(_members[key]!.containsKey)) {
            return '$key.${keys.first}';
          }
        }
      }
    }
    return null;
  }

  void apply(CompilationUnit unit, String text) {
    for (final directive in unit.directives) {
      if (directive is ImportDirective) {
        _imports.add(text.substring(directive.offset, directive.end));
      }
    }
    for (final declaration in unit.declarations) {
      if (!_isPatch(declaration)) {
        _added.add(_textOf(text, declaration));
        continue;
      }
      switch (declaration) {
        case ClassDeclaration() || MixinDeclaration() || ExtensionDeclaration():
          _applyMembers(text, declaration);
        default:
          for (final key in _keysOf(declaration)) {
            _replace(_declarations[key]!, _textOf(text, declaration));
          }
      }
    }
  }

  void _applyMembers(String text, CompilationUnitMember declaration) {
    final name = _keysOf(declaration).single;
    final target = _declarations[name]!;
    final annotations = _annotationsOf(text, declaration);
    if (annotations.isNotEmpty) {
      final at = target.$2.firstTokenAfterCommentAndMetadata.offset;
      _edit(target.$1, at, at, '$annotations ');
    }
    for (final member in _membersOf(declaration)) {
      final own = _textOf(text, member);
      if (_isPatch(member)) {
        _patchMember(name, member, own);
      } else {
        final end = _bodyOf(target.$2)!.offset;
        _edit(target.$1, end, end, '\n$own\n');
      }
    }
  }

  void _patchMember(String name, ClassMember member, String text) {
    final members = _members[name]!;
    final keys = _memberKeys(member);
    final targets = {for (final key in keys) ?members[key]};

    for (final (i, target) in targets.indexed) {
      _replace(target, i == 0 ? text : '');
    }
  }

  void _replace((String, AnnotatedNode) target, String text) {
    final (file, node) = target;
    final start = node.metadata.isEmpty
        ? node.firstTokenAfterCommentAndMetadata.offset
        : node.metadata.first.offset;
    _edit(file, start, node.end, text);
  }

  void _edit(String file, int start, int end, String text) =>
      (_edits[file] ??= []).add((start, end, text));

  Map<String, String> result(String main, String added) {
    final unit = _units[main]!;
    final hasAdded = _added.isNotEmpty;
    final imports = unit.directives.whereType<NamespaceDirective>();
    final library = unit.directives.whereType<LibraryDirective>();
    final lastImport = imports.lastOrNull ?? library.firstOrNull;
    if (_imports.isNotEmpty) {
      final at = lastImport?.end ?? 0;
      _edit(main, at, at, '\n${_imports.join('\n')}');
    }
    if (hasAdded) {
      final at = unit.directives.lastOrNull?.end ?? 0;
      _edit(main, at, at, "\npart '$added';");
    }
    return {
      for (final MapEntry(key: path, value: text) in _files.entries)
        path: _apply(text, _edits[path] ?? const []),
      if (hasAdded) added: "part of '$main';\n\n${_added.join('\n\n')}\n",
    };
  }

  static String _apply(String text, List<(int, int, String)> edits) {
    // Of edits at one place, insertions come first.
    final ordered = edits.indexed.toList()
      ..sort((a, b) {
        final (_, (aStart, aEnd, _)) = a;
        final (_, (bStart, bEnd, _)) = b;
        final order = aStart.compareTo(bStart);
        if (order != 0) return order;
        if ((aEnd == aStart) != (bEnd == bStart)) return aEnd.compareTo(bEnd);
        return a.$1.compareTo(b.$1);
      });
    final result = StringBuffer();
    var copied = 0;
    for (final (_, (start, end, replacement)) in ordered) {
      result
        ..write(text.substring(copied, start))
        ..write(replacement);
      copied = end;
    }
    result.write(text.substring(copied));
    return '$result';
  }

  static bool _isPatch(AnnotatedNode node) =>
      node.metadata.any((annotation) => annotation.name.name == 'patch');

  /// The annotations of [node] but `@patch`.
  static String _annotationsOf(String text, AnnotatedNode node) => [
    for (final annotation in node.metadata)
      if (annotation.name.name != 'patch')
        text.substring(annotation.offset, annotation.end),
  ].join(' ');

  static String _textOf(String text, AnnotatedNode node) {
    final start = node.firstTokenAfterCommentAndMetadata.offset;
    final annotations = _annotationsOf(text, node);
    final own = text.substring(start, node.end);
    return annotations.isEmpty ? own : '$annotations $own';
  }

  static List<ClassMember> _membersOf(CompilationUnitMember node) =>
      switch (node) {
        ClassDeclaration(:final body) ||
        MixinDeclaration(:final body) ||
        ExtensionDeclaration(:final body) ||
        ExtensionTypeDeclaration(:final body) => body.members,
        EnumDeclaration(:final body) => body.members,
        _ => const [],
      };

  /// What ends the members of [node].
  static Token? _bodyOf(CompilationUnitMember node) => switch (node) {
    ClassDeclaration(body: BlockClassBody(:final rightBracket)) ||
    MixinDeclaration(body: BlockClassBody(:final rightBracket)) ||
    ExtensionDeclaration(
      body: BlockClassBody(:final rightBracket),
    ) => rightBracket,
    _ => null,
  };

  static List<String> _keysOf(CompilationUnitMember node) => switch (node) {
    ClassDeclaration(:final namePart) => [namePart.typeName.lexeme],
    MixinDeclaration(:final name) ||
    ClassTypeAlias(:final name) ||
    GenericTypeAlias(:final name) ||
    FunctionTypeAlias(:final name) => [name.lexeme],
    EnumDeclaration(:final namePart) => [namePart.typeName.lexeme],
    ExtensionDeclaration(:final name?) => [name.lexeme],
    FunctionDeclaration(:final name, :final isSetter) => [
      isSetter ? '${name.lexeme}=' : name.lexeme,
    ],
    TopLevelVariableDeclaration(:final variables) => _variableKeys(variables),
    _ => const [],
  };

  /// The names of what [node] declares; a field has those of its getter and
  /// setter.
  static List<String> _memberKeys(ClassMember node) => switch (node) {
    MethodDeclaration(:final name, isSetter: true) => ['${name.lexeme}='],
    MethodDeclaration(
      :final name,
      isOperator: true,
      parameters: FormalParameterList(parameters: []),
    ) =>
      ['unary ${name.lexeme}'],
    MethodDeclaration(:final name) => [name.lexeme],
    ConstructorDeclaration(:final name) => ['new ${name?.lexeme ?? ''}'],
    FieldDeclaration(:final fields) => _variableKeys(fields),
    _ => const [],
  };

  static List<String> _variableKeys(VariableDeclarationList list) => [
    for (final variable in list.variables) ...[
      variable.name.lexeme,
      '${variable.name.lexeme}=',
    ],
  ];
}
