import 'dart:typed_data';

import 'package:dartc/hir.dart';

/// The 64 bits of [value].
int bitsOf(double value) => (ByteData(8)..setFloat64(0, value)).getInt64(0);

/// What [instruction] gives without being done, or what does the same with less,
/// or itself.
///
/// The result is among its inputs or a new instruction.
HirValue reduce(HirInstruction instruction) => switch (instruction) {
  HirIntBinary() => _integer(instruction),
  HirFloatBinary() => _float(instruction),
  HirBoolBinary() => _boolean(instruction),
  HirUnary() => _unary(instruction),
  HirCompare() => _compare(instruction),
  HirUnbox(object: HirBox(:final value)) => value,
  HirBox(:final target, value: HirUnbox(:final field, :final object))
      when target.fields.single == field =>
    object,
  HirMachine(op: .isSame, arguments: [final left, final right]) => reduce(
    HirCompare(.equal, left, right),
  ),
  HirLoad(:final field, object: HirStatic(:final object))
      when object.fields[field] != null =>
    _constant(object.fields[field]!),
  HirUnbox(:final field, object: HirStatic(:final object))
      when object.fields.containsKey(field) =>
    _constant(object.fields[field]!),
  HirLength(array: HirStatic(:final object)) => HirConst(
    object.elements!.length,
  ),
  HirLength(array: HirNewArray(:final length)) => length,
  _ => instruction,
};

HirInstruction _constant(Object value) => switch (value) {
  HirConstObject() => HirStatic(value),
  _ => HirConst(value),
};

bool _isConstant(HirValue value, Object constant) =>
    value is HirConst && value.value == constant;

HirValue _integer(HirIntBinary binary) {
  final HirIntBinary(:operator, :left, :right) = binary;
  if (left is HirConst && right is HirConst) {
    final result = _foldIntegers(
      operator,
      left.value as int,
      right.value as int,
    );
    return result == null ? binary : HirConst(result);
  }
  final isSame = identical(left, right);
  return switch (operator) {
    .add || .or || .xor when _isConstant(left, 0) => right,
    .add ||
    .subtract ||
    .or ||
    .xor ||
    .shiftLeft ||
    .shiftRight ||
    .shiftRightUnsigned when _isConstant(right, 0) => left,
    .multiply when _isConstant(left, 1) => right,
    .multiply || .divide when _isConstant(right, 1) => left,
    .and when _isConstant(left, -1) => right,
    .and when _isConstant(right, -1) => left,
    .and || .or when isSame => left,
    .subtract || .xor when isSame => HirConst(0),
    .multiply || .and when _isConstant(left, 0) => left,
    .multiply || .and when _isConstant(right, 0) => right,
    _ => binary,
  };
}

int? _foldIntegers(HirIntOperator operator, int left, int right) =>
    switch (operator) {
      .add => left + right,
      .subtract => left - right,
      .multiply => left * right,
      .divide => right == 0 ? null : left ~/ right,
      .modulo => right == 0 ? null : left % right,
      .and => left & right,
      .or => left | right,
      .xor => left ^ right,
      .shiftLeft => right < 0 ? null : left << right,
      .shiftRight => right < 0 ? null : left >> right,
      .shiftRightUnsigned => right < 0 ? null : left >>> right,
    };

HirValue _float(HirFloatBinary binary) {
  final HirFloatBinary(:operator, :left, :right) = binary;
  if (left is! HirConst || right is! HirConst) return binary;
  final a = left.value as double, b = right.value as double;
  return HirConst(switch (operator) {
    .add => a + b,
    .subtract => a - b,
    .multiply => a * b,
    .divide => a / b,
    .modulo => a % b,
  });
}

HirValue _boolean(HirBoolBinary binary) {
  final HirBoolBinary(:operator, :left, :right) = binary;
  for (final (constant, other) in [(left, right), (right, left)]) {
    if (constant is! HirConst) continue;
    final isTrue = constant.value as bool;
    return switch (operator) {
      .and => isTrue ? other : constant,
      .or => isTrue ? constant : other,
      .xor => isTrue ? reduce(HirUnary(.not, other)) : other,
    };
  }
  if (!identical(left, right)) return binary;
  return operator == .xor ? HirConst(false) : left;
}

HirValue _unary(HirUnary unary) {
  final HirUnary(:operator, :operand) = unary;
  if (operand is HirUnary && operand.operator == operator) {
    if (operator == .not || operator == .negateInt || operator == .complement) {
      return operand.operand;
    }
  }
  if (operator == .not && operand is HirCompare) {
    final HirCompare(:relation, :left, :right) = operand;
    // Comparisons of doubles may all be false.
    if (relation.isEquality || left.type == .integer) {
      return HirCompare(_opposite(relation), left, right);
    }
  }
  if (operand is! HirConst) return unary;
  final value = operand.value;
  return switch (operator) {
    .negateInt => HirConst(-(value as int)),
    .complement => HirConst(~(value as int)),
    .negateFloat => HirConst(-(value as double)),
    .not => HirConst(!(value as bool)),
    .intToFloat => HirConst((value as int).toDouble()),
    _ => unary,
  };
}

HirRelation _opposite(HirRelation relation) => switch (relation) {
  .equal => .notEqual,
  .notEqual => .equal,
  .less => .greaterOrEqual,
  .lessOrEqual => .greater,
  .greater => .lessOrEqual,
  .greaterOrEqual => .less,
};

HirValue _compare(HirCompare compare) {
  final HirCompare(:relation, :left, :right) = compare;
  if (left is HirConst && right is HirConst) {
    return HirConst(_holds(relation, left.value, right.value));
  }
  if (left.type == .reference) return _identity(compare);
  if (left.type == .boolean) {
    for (final (constant, other) in [(left, right), (right, left)]) {
      if (constant is! HirConst) continue;
      return constant.value == (relation == .equal)
          ? other
          : reduce(HirUnary(.not, other));
    }
  }
  // NaN is not equal to itself.
  if (identical(left, right) && left.type != .float) {
    return HirConst(
      relation == .equal ||
          relation == .lessOrEqual ||
          relation == .greaterOrEqual,
    );
  }
  return compare;
}

bool _holds(HirRelation relation, Object a, Object b) {
  if (relation.isEquality) return (a == b) == (relation == .equal);
  a as num;
  b as num;
  return switch (relation) {
    .less => a < b,
    .lessOrEqual => a <= b,
    .greater => a > b,
    _ => a >= b,
  };
}

/// Whether [value] is certainly an object, and not null.
bool isObject(HirValue value) =>
    value is HirNew ||
    value is HirNewArray ||
    value is HirBox ||
    value is HirStatic;

HirValue _identity(HirCompare compare) {
  final HirCompare(:relation, :left, :right) = compare;
  final bool isSame;
  if (identical(left, right) || left is HirNull && right is HirNull) {
    isSame = true;
  } else if (left is HirNull && isObject(right) ||
      right is HirNull && isObject(left)) {
    isSame = false;
  } else {
    return compare;
  }
  return HirConst(isSame == (relation == .equal));
}
