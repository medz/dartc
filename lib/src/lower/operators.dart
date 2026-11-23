import 'package:dartc/hir.dart';
import 'package:dartc/lir.dart';

import 'system.dart';

/// Lowers operators, adding their instructions to [block].
final class OperatorLowering(final LirBlock block) {
  LirValue _int(int value) => block.add(ConstInt(value));

  LirValue _apply(IntOp op, LirValue left, LirValue right) =>
      block.add(IntBinary(op, left, right));

  /// [constant] is the value of [right] where it is known.
  LirValue integer(
    HirIntOperator operator,
    LirValue left,
    LirValue right,
    int? constant,
  ) {
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
    if (operator.isShift && constant! > 63) {
      // Every bit is shifted out, leaving zeros or copies of the sign.
      return op == .sar ? _apply(.sar, left, _int(63)) : _int(0);
    }
    final result = _apply(op, left, right);
    if (operator != .modulo) return result;
    // A negative remainder is moved up by the divisor's magnitude, which
    // wraps to the right value even for the smallest int.
    final magnitude = _int(constant! < 0 ? -constant : constant);
    final ifNegative = _apply(.sar, result, _int(63));
    return _apply(.add, result, _apply(.and, ifNegative, magnitude));
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
      };

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
