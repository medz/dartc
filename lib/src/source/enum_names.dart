import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import 'corrected_text.dart';

const _prefix = '_name\$dartc';
final _fieldNames = RegExp('${RegExp.escape(_prefix)}[0-9]*');

/// Finds a private name that does not occur in any original unit of a library.
String unusedEnumNameField(Iterable<String> contents) {
  final used = {
    for (final text in contents)
      for (final match in _fieldNames.allMatches(text)) match[0]!,
  };
  var name = _prefix;
  for (var suffix = 0; used.contains(name); suffix++) {
    name = '$_prefix$suffix';
  }
  return name;
}

/// Adds a second field to preserve the value of an enum's own `_name` field.
///
/// The analyzer puts the name of the enum constant in place of that value.
final class EnumNames(
  final String Function() _name,
  final String Function(Expression node) _textOf,
) extends SimpleAstVisitor<void> {
  final edits = <Edit>[];
  final fields = <String, String>{};
  late final _field = _name();

  void _insert(int offset, String text) =>
      edits.add((offset: offset, end: offset, text: text));

  @override
  void visitEnumDeclaration(EnumDeclaration node) {
    final element = node.declaredFragment?.element;
    final name = element?.name;
    if (element == null ||
        name == null ||
        !element.fields.any(
          (field) =>
              field.name == '_name' &&
              !field.isStatic &&
              (field.isOriginDeclaration ||
                  field.isOriginDeclaringFormalParameter),
        )) {
      return;
    }
    fields[name] = _field;
    final members = node.body.members;
    var isInitialized = false;
    for (final FieldDeclaration(:fields)
        in members.whereType<FieldDeclaration>()) {
      for (final variable in fields.variables) {
        if (variable.name.lexeme != '_name') continue;
        final value = variable.initializer;
        isInitialized = value != null;
        final own = value == null ? '' : ' = ${_textOf(value)}';
        _insert(variable.end, ', $_field$own');
      }
    }
    if (isInitialized) return;
    for (final member in members) {
      switch (member) {
        case ConstructorDeclaration(
          factoryKeyword: null,
          :final parameters,
          :final initializers,
        ):
          _initialize(parameters, initializers, parameters.end);
        default:
          break;
      }
    }
    if (node.namePart case final PrimaryConstructorDeclaration primary) {
      _primary(node, primary);
    }
  }

  /// Has constructors give the other field a value, too. If they have no other
  /// [initializers], this starts at [offset].
  void _initialize(
    FormalParameterList parameters,
    List<ConstructorInitializer> initializers,
    int offset,
  ) {
    if (initializers.any((i) => i is RedirectingConstructorInvocation)) return;
    for (final initializer in initializers) {
      if (initializer is! ConstructorFieldInitializer) continue;
      if (initializer.fieldName.name != '_name') continue;
      final value = _textOf(initializer.expression);
      return _insert(initializer.end, ', $_field = $value');
    }
    if (!parameters.parameters.any((p) => p.name?.lexeme == '_name')) return;
    final value = '$_field = _name';
    if (initializers.isEmpty) {
      _insert(offset, ': $value');
    } else {
      _insert(initializers.last.end, ', $value');
    }
  }

  void _primary(EnumDeclaration node, PrimaryConstructorDeclaration primary) {
    final EnumDeclaration(:body) = node;
    if (body is! BlockEnumBody) return;
    final added = StringBuffer(body.semicolon == null ? ';' : '');
    if (!body.members.any(_declaresField)) {
      added.write(' final Object? $_field;');
    }
    if (primary.body case final own?) {
      final at = own.colon?.end ?? own.thisKeyword.end;
      _initialize(primary.formalParameters, own.initializers, at);
    } else {
      added.write(' this : $_field = _name;');
    }
    _insert(body.rightBracket.offset, '$added');
  }

  static bool _declaresField(ClassMember member) =>
      member is FieldDeclaration &&
      member.fields.variables.any((v) => v.name.lexeme == '_name');
}
