import 'package:dartc/hir.dart';
import 'package:dartc/lir.dart';

import 'system.dart';

/// Lowers operators, adding their instructions to [block].
final class OperatorLowering(final LirBlock block) {
  LirValue _int(int value) => block.add(ConstInt(value));

  LirValue _apply(IntOp op, LirValue left, LirValue right) =>
      block.add(IntBinary(op, left, right));

  LirValue integer(HirIntOperator operator, LirValue left, LirValue right) {
    final IntOp op = switch (operator) {
      .add => .add,
      .subtract => .sub,
      .multiply => .mul,
      .divide => .div,
      .modulo => .rem,
      .and => .and,
      .or => .or,
      .xor => .xor,
      .shiftLeft => .shl,
      .shiftRight => .sar,
      .shiftRightUnsigned => .shr,
    };
    if (operator.isShift) return _shift(op, left, right);
    final result = _apply(op, left, right);
    if (operator != .modulo) return result;
    // A negative remainder is moved up by the divisor's magnitude, which
    // wraps to the right value even for the smallest int.
    final sign = _apply(.sar, right, _int(63));
    final magnitude = _apply(.sub, _apply(.xor, right, sign), sign);
    final ifNegative = _apply(.sar, result, _int(63));
    return _apply(.add, result, _apply(.and, ifNegative, magnitude));
  }

  /// Beyond 63, every bit is shifted out, leaving zeros or copies of the sign.
  LirValue _shift(IntOp op, LirValue left, LirValue right) {
    final most = _int(63);
    if (right case ConstInt(:final value)) {
      if (value <= 63) return _apply(op, left, right);
      return op == .sar ? _apply(.sar, left, most) : _int(0);
    }
    final isFar = block.add(Compare(.gt, right, most));
    if (op == .sar) {
      final all = _apply(.sub, _int(0), isFar);
      return _apply(.sar, left, _apply(.and, _apply(.or, right, all), most));
    }
    final shifted = _apply(op, left, _apply(.and, right, most));
    return _apply(.and, shifted, _apply(.sub, isFar, _int(1)));
  }

  LirValue float(HirFloatOperator operator, LirValue left, LirValue right) {
    if (operator == .modulo) return _floatModulo(left, right);
    final FloatOp op = switch (operator) {
      .add => .add,
      .subtract => .sub,
      .multiply => .mul,
      _ => .div,
    };
    return block.add(FloatBinary(op, left, right));
  }

  /// The remainder, moved up by the divisor's magnitude if it is negative.
  LirValue _floatModulo(LirValue left, LirValue right) {
    final rest = block.add(callSystem('fmod', [left, right]));
    final bits = block.add(Convert(.floatBitsToInt, right));
    final magnitude = _apply(.and, bits, _int(0x7fffffffffffffff));
    final zero = block.add(ConstFloat(0));
    final negative = block.add(Compare(.lt, rest, zero));
    final mask = _apply(.sub, _int(0), negative);
    final added = block.add(
      Convert(.intBitsToFloat, _apply(.and, magnitude, mask)),
    );
    // Adding 0 also turns a remainder of -0.0 into 0.0.
    return block.add(FloatBinary(.add, rest, added));
  }

  LirValue boolean(HirBoolOperator operator, LirValue left, LirValue right) {
    final IntOp op = switch (operator) {
      .and => .and,
      .or => .or,
      .xor => .xor,
    };
    return _apply(op, left, right);
  }

  LirValue unary(HirUnaryOperator operator, LirValue operand) =>
      switch (operator) {
        .negateInt => _apply(.sub, _int(0), operand),
        .complement => _apply(.xor, operand, _int(-1)),
        .negateFloat => block.add(FloatUnary(.neg, operand)),
        .not => _apply(.xor, operand, _int(1)),
        .intToFloat => block.add(Convert(.intToFloat, operand)),
        .floatToInt => _truncate(operand),
      };

  /// Takes the place of values beyond the range of `int` by its ends.
  LirValue _truncate(LirValue operand) {
    LirValue float(double value) => block.add(ConstFloat(value));
    const limit = 9223372036854775808.0;
    final isLow = block.add(Compare(.lt, operand, float(-limit)));
    final isHigh = block.add(Compare(.ge, operand, float(limit)));
    final isInside = _apply(.sub, _apply(.or, isLow, isHigh), _int(1));
    final bits = block.add(Convert(.floatBitsToInt, operand));
    final inside = block.add(
      Convert(.intBitsToFloat, _apply(.and, bits, isInside)),
    );
    final whole = block.add(Convert(.floatToInt, inside));
    // The largest int, or the smallest, which follows it by wrapping.
    final end = _apply(.add, _int(0x7fffffffffffffff), isLow);
    final outside = _apply(.xor, isInside, _int(-1));
    return _apply(.or, whole, _apply(.and, end, outside));
  }

  LirValue compare(HirRelation relation, LirValue left, LirValue right) {
    final Relation found = switch (relation) {
      .equal => .eq,
      .notEqual => .ne,
      .less => .lt,
      .lessOrEqual => .le,
      .greater => .gt,
      .greaterOrEqual => .ge,
    };
    return block.add(Compare(found, left, right));
  }
}
