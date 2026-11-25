import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';

import 'corrected_text.dart';

const _prefix = '_name\$dartc';
final _fieldNames = RegExp('${RegExp.escape(_prefix)}[0-9]*');

/// Allocates a distinct unused companion field name for each enum in a library.
String Function(EnumElement) enumNameFields(Iterable<String> contents) {
  final used = {
    for (final text in contents)
      for (final match in _fieldNames.allMatches(text)) match[0]!,
  };
  final names = <EnumElement, String>{};
  var suffix = -1;
  return (element) => names.putIfAbsent(element, () {
    String name;
    do {
      name = suffix < 0 ? _prefix : '$_prefix$suffix';
      suffix++;
    } while (used.contains(name));
    return name;
  });
}

/// Adds a second field to preserve the value of an enum's own `_name` field.
///
/// The analyzer puts the name of the enum constant in place of that value.
final class EnumNames(
  final String Function(EnumElement) _name,
  final String Function(Expression node) _textOf,
) extends SimpleAstVisitor<void> {
  final edits = <Edit>[];
  final fields = <String, String>{};

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
    final field = fields[name] = _name(element);
    final members = node.body.members;
    var isInitialized = false;
    for (final FieldDeclaration(:fields)
        in members.whereType<FieldDeclaration>()) {
      for (final variable in fields.variables) {
        if (variable.name.lexeme != '_name') continue;
        final value = variable.initializer;
        isInitialized = value != null;
        final own = value == null ? '' : ' = ${_textOf(value)}';
        _insert(variable.end, ', $field$own');
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
          _initialize(parameters, initializers, parameters.end, field);
        default:
          break;
      }
    }
    if (node.namePart case final PrimaryConstructorDeclaration primary) {
      _primary(node, primary, field);
    }
  }

  /// Has constructors give the other field a value, too. If they have no other
  /// [initializers], this starts at [offset].
  void _initialize(
    FormalParameterList parameters,
    List<ConstructorInitializer> initializers,
    int offset,
    String field,
  ) {
    if (initializers.any((i) => i is RedirectingConstructorInvocation)) return;
    for (final initializer in initializers) {
      if (initializer is! ConstructorFieldInitializer) continue;
      if (initializer.fieldName.name != '_name') continue;
      final value = _textOf(initializer.expression);
      return _insert(initializer.end, ', $field = $value');
    }
    if (!parameters.parameters.any((p) => p.name?.lexeme == '_name')) return;
    final value = '$field = _name';
    if (initializers.isEmpty) {
      _insert(offset, ': $value');
    } else {
      _insert(initializers.last.end, ', $value');
    }
  }

  void _primary(
    EnumDeclaration node,
    PrimaryConstructorDeclaration primary,
    String field,
  ) {
    final EnumDeclaration(:body) = node;
    if (body is! BlockEnumBody) return;
    final added = StringBuffer(body.semicolon == null ? ';' : '');
    if (!body.members.any(_declaresField)) {
      added.write(' final Object? $field;');
    }
    if (primary.body case final own?) {
      final at = own.colon?.end ?? own.thisKeyword.end;
      _initialize(primary.formalParameters, own.initializers, at, field);
    } else {
      added.write(' this : $field = _name;');
    }
    _insert(body.rightBracket.offset, '$added');
  }

  static bool _declaresField(ClassMember member) =>
      member is FieldDeclaration &&
      member.fields.variables.any((v) => v.name.lexeme == '_name');
}
