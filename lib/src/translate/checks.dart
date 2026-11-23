import 'package:dartc/hir.dart';

import 'builder.dart';
import 'builtin_error.dart';
import 'scope.dart';

/// Adds operations that throw for some operands, with their checks.
final class CheckedOperations(
  final ProgramScope _scope,
  final FunctionBuilder _builder,
) {
  HirValue _int(int value) => _builder.add(HirConst(value));

  HirValue _compare(HirRelation relation, HirValue left, HirValue right) =>
      _builder.add(HirCompare(relation, left, right));

  void _throwIf(
    HirValue failed,
    BuiltinError error, [
    List<HirValue> arguments = const [],
  ]) => _builder.throwIf(failed, _scope.throwerOf(error), arguments);

  HirValue integer(HirIntOperator operator, HirValue left, HirValue right) {
    final known = right is HirConst ? right.value as int : null;
    if (operator.isDivision && (known == null || known == 0)) {
      _throwIf(_compare(.equal, right, _int(0)), .divisionByZero);
    }
    if (operator.isShift && (known == null || known < 0)) {
      _throwIf(_compare(.less, right, _int(0)), .negativeShift, [right]);
    }
    return _builder.add(HirIntBinary(operator, left, right));
  }

  /// The `int` that [value] is nearest to, towards zero.
  HirValue toInt(HirValue value) {
    if (value.type == .integer) return value;
    // Only infinities and NaN differ from themselves by something else than 0.
    final difference = _builder.add(HirFloatBinary(.subtract, value, value));
    _throwIf(_compare(.notEqual, difference, difference), .noInt);
    return _builder.add(HirUnary(.floatToInt, value));
  }

  /// The object [value], which is not null.
  HirValue notNull(HirValue value) {
    if (value.type != .reference) return value;
    _throwIf(_compare(.equal, value, _builder.add(HirNull())), .nullCheck);
    return value;
  }
}
