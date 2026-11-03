import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/ast/token.dart' show Token;
import 'package:analyzer/dart/element/type.dart' as dart;
import 'package:dartc/ir.dart';

import 'bindings.dart';
import 'function_context.dart';

/// Reads a record slot, reusing its stored operand when the construction is visible.
Value readRecordField(FunctionContext context, Value record, int slot) =>
    switch (record) {
      MakeRecord(:final inputs) => inputs[slot],
      RecordConstant(:final fields) => fields[slot],
      _ => context.current!.emit(RecordGet(record, slot)),
    };

/// Evaluates record fields in source order and places their values in canonical slots.
Value? lowerRecord(
  FunctionContext context,
  ast.RecordLiteral literal,
  Value? Function(ast.Expression) evaluate,
) {
  if (literal.isConst) {
    return constantValue(
      literal.computeConstantValue()?.value,
      context.unit,
      literal,
    );
  }
  final type =
      valueType(literal.staticType!, context.unit, literal) as RecordType;
  final fields = List<Value?>.filled(type.fields.length, null);
  var positional = 0;
  for (final field in literal.fields) {
    final value = evaluate(field.fieldExpression);
    if (value == null) return null;
    final slot = field is ast.RecordLiteralNamedField
        ? type.slots[field.name.lexeme]!
        : positional++;
    fields[slot] = value;
  }
  return context.current!.emit(MakeRecord(type, fields.cast<Value>()));
}

/// Lowers field getters and postfix assertions in one null-shorting chain.
Value? lowerSelectors(
  FunctionContext context,
  ast.Expression root,
  Value? Function(ast.Expression) evaluate,
) {
  JumpTarget? skipped;
  Value? visit(ast.Expression node) {
    if (node case ast.PostfixExpression(
      operator: Token(type: .BANG),
      :final operand,
    )) {
      final value = visit(operand);
      return value == null ? null : context.normal(context.checkNotNull(value));
    }
    final field = switch (node) {
      ast.PrefixedIdentifier(:final prefix, :final identifier)
          when prefix.staticType is dart.RecordType =>
        (prefix, identifier.name, false),
      ast.PropertyAccess(
        target: final target?,
        :final propertyName,
        :final isNullAware,
        isCascaded: false,
      )
          when target.staticType is dart.RecordType =>
        (target, propertyName.name, isNullAware),
      _ => null,
    };
    if (field == null) {
      if (identical(node, root)) {
        unsupported(context.unit, node, 'property access');
      }
      return evaluate(node);
    }
    final (receiver, name, nullAware) = field;
    final value = visit(receiver);
    if (value == null) return null;
    if (nullAware) {
      skipped ??= JumpTarget(context, [
        valueType(root.staticType!, context.unit, root),
      ]);
      context.guard(
        context.testType(value, .nullType, negated: true),
        skipped!,
        [const Constant.nullValue()],
      );
      if (context.current == null) return null;
    }
    final known = context.refined(value);
    final owner = switch (known.type.nonNullable) {
      final RecordType type => type,
      _ =>
        valueType(receiver.staticType!, context.unit, receiver).nonNullable
            as RecordType,
    };
    final slot = owner.slots[name];
    if (slot == null) unsupported(context.unit, node, 'record member $name');
    final record = context.normal(context.cast(known, owner));
    return record == null
        ? null
        : context.normal(readRecordField(context, record, slot));
  }

  final result = visit(root);
  final exit = skipped;
  if (exit == null || !exit.hasIncoming) return result;
  if (result != null) exit.jump([result]);
  return exit.enter()!.parameters.first;
}
