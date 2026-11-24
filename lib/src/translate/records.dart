import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';

import 'builder.dart';
import 'conversions.dart';
import 'scope.dart';
import 'types.dart';

/// The names of the named fields of [type], in the order of objects.
List<String> fieldNames(RecordType type) =>
    type.namedFields.map((field) => field.name).toList()..sort();

/// The types of the fields of [type], in the order of objects.
List<DartType> fieldTypes(RecordType type) => [
  for (final field in type.positionalFields) field.type,
  for (final name in fieldNames(type))
    type.namedFields.firstWhere((field) => field.name == name).type,
];

/// The place of the field [name] of records of [type], if they have one.
int? fieldIndex(DartType? type, String name) {
  final record = type == null ? null : boundOf(type);
  if (record is! RecordType) return null;
  final count = record.positionalFields.length;
  final at = fieldNames(record).indexOf(name);
  if (at >= 0) return count + at;
  for (var i = 0; i < count; i++) {
    if (name == '\$${i + 1}') return i;
  }
  return null;
}

/// Translates records, which are arrays of their fields.
final class RecordTranslator(
  final ProgramScope _scope,
  final FunctionBuilder _builder,
  final Evaluator _evaluator,
) {
  late final _conversions = Conversions(_scope, _builder);

  HirValue create(RecordLiteral node) {
    final type = node.staticType as RecordType, types = fieldTypes(type);
    final values = <int, HirValue>{};
    var position = 0;
    for (final field in node.fields) {
      final name = field is RecordLiteralNamedField
          ? field.name.lexeme
          : '\$${++position}';
      final index = fieldIndex(type, name)!;
      final expression = field.fieldExpression;
      values[index] = _evaluator.valueAsObject(expression, types[index]);
    }
    return _scope.record(_builder, fieldNames(type), [
      for (var i = 0; i < types.length; i++) values[i]!,
    ]);
  }

  /// The field [name] of [record], which is of [type], if it has one.
  HirValue? field(HirValue record, DartType? type, String name) {
    final index = fieldIndex(type, name);
    if (index == null) return null;
    final found = fieldTypes(boundOf(type!) as RecordType)[index];
    final value = _builder.add(
      HirLoadElement(.reference, record, _builder.add(HirConst(index))),
    );
    return _conversions.coerce(value, valueType(found)!);
  }
}
