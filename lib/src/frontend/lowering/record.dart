import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:dartc/ir.dart';

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
    return context.bindings.constantExpression(context.unit, literal);
  }
  final type = context.typeOf(literal.staticType!, literal) as RecordType;
  final fields = List<Value?>.filled(type.fields.length, null);
  var positional = 0;
  for (final field in literal.fields) {
    final value = evaluate(field.fieldExpression);
    if (value == null) return null;
    final slot = field is ast.RecordLiteralNamedField
        ? type.slots[field.name.lexeme]!
        : positional++;
    final converted = context.normal(context.convert(value, type.fields[slot]));
    if (converted == null) return null;
    fields[slot] = converted;
  }
  return context.emit(MakeRecord(type, fields.cast<Value>()));
}
