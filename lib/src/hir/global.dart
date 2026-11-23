import 'class.dart';
import 'value.dart';

/// An object known when compiling, which never changes.
///
/// [fields] gives every field an `int`, `double`, `bool`, null or another
/// constant. Constants are told apart by themselves.
final class HirConstObject(
  final HirClass target,
  Map<HirField, Object?> fields,
) {
  final Map<HirField, Object?> fields = .unmodifiable(fields);

  @override
  String toString() =>
      '${target.name}(${target.fields.map((f) => fields[f]).join(', ')})';
}

/// A variable of the whole program, starting with [initial], which is like
/// the fields of a constant.
final class HirGlobal(
  final String name,
  final HirType type,
  final Object? initial,
);

/// Whether a constant's field or a global of [type] can be [value].
bool isConstant(HirType type, Object? value) => switch (type) {
  .integer => value is int,
  .float => value is double,
  .boolean => value is bool,
  .reference => value == null || value is HirConstObject,
};
