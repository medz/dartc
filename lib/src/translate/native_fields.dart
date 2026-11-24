import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';
import 'package:dartc/native.dart';

import 'builder.dart';
import 'conversions.dart';
import 'native_types.dart';
import 'native_values.dart';
import 'scope.dart';

/// Uses the fields that structs and unions have in memory.
final class NativeFields(
  final ProgramScope _scope,
  final FunctionBuilder _builder,
) {
  late final _conversions = Conversions(_scope, _builder);
  late final _values = NativeValues(_scope, _builder);

  HirValue _number(int value) => _builder.add(HirConst(value));

  HirValue _call(String name, List<HirValue> arguments, {HirValue? types}) =>
      _builder.call(HirCall(_scope.runtime(name), [?types, ...arguments]))!;

  HirValue _address(HirValue object, NativeField field) => _builder.add(
    HirIntBinary(.add, _values.addressOf(object), _number(field.offset)),
  );

  /// Reads [field] of [object].
  HirValue load(NativeField field, HirValue object) {
    final (:element, :offset, :type, :dimensions) = field;
    if (type is! NativeCompound && type is! NativeArray) {
      return _values.loadScalar(_address(object, field), type, element.type);
    }
    final base = _call('baseOf', [object]);
    final start = _builder.add(
      HirIntBinary(.add, _call('offsetOf', [object]), _number(offset)),
    );
    if (type is NativeCompound) return _values.wrap(base, element.type, start);
    final own = (element.type as InterfaceType).typeArguments;
    final integers = _conversions.types.intType;
    return _call('newArray', [
      base,
      start,
      _builder.add(HirConst(dimensions.first == 0)),
      _scope.list(_builder, integers, [
        for (final size in dimensions)
          _conversions.coerce(_number(size), .reference),
      ]),
    ], types: _scope.typeList(_builder, own));
  }

  /// Assigns [value] to [field] of [object].
  void store(NativeField field, HirValue object, HirValue value) {
    final (element: _, :offset, :type, dimensions: _) = field;
    switch (type) {
      case NativeCompound() || NativeArray():
        _call('assignCompound', [
          object,
          _number(offset),
          value,
          _number(type.size),
        ]);
      case NativePointer():
        final address = _call('pointerAddress', [value]);
        _values.storeScalar(_address(object, field), type, address);
      default:
        final given = _values.prepare(value, type, isByAddress: false);
        _values.storeScalar(_address(object, field), type, given);
    }
  }
}
