import 'package:analyzer/dart/ast/ast.dart';
import 'package:dartc/hir.dart';

import 'builder.dart';

/// Translates operators on numbers and booleans.
final class OperatorTranslator(final FunctionBuilder _builder) {
  Never _unsupported(AstNode node, String what) =>
      throw _builder.unit.unsupported(node, what);

  HirValue unary(AstNode node, String operator, HirValue operand) {
    final HirUnaryOperator found = switch ((operator, operand.type)) {
      ('-', .integer) => .negateInt,
      ('-', .float) => .negateFloat,
      ('~', .integer) => .complement,
      ('!', .boolean) => .not,
      _ => _unsupported(node, 'operator $operator'),
    };
    return _builder.add(HirUnary(found, operand));
  }

  /// Applies a binary operator, other than `&&`, `||` and `??`.
  HirValue binary(
    AstNode node,
    String operator,
    HirValue left,
    HirValue right,
  ) {
    if (left.type == .boolean && right.type == .boolean) {
      return _boolean(node, operator, left, right);
    }
    if (left.type == .boolean || right.type == .boolean) {
      _unsupported(node, 'operator $operator on these types');
    }
    final bothInt = left.type == .integer && right.type == .integer;
    if (bothInt && operator != '/') {
      return _compare(operator, left, right) ??
          _integer(node, operator, left, right);
    }
    // An int meeting a double, or divided by an int, is converted.
    final a = _toFloat(left), b = _toFloat(right);
    return _compare(operator, a, b) ?? _float(node, operator, a, b);
  }

  HirValue _toFloat(HirValue value) =>
      value.type == .float ? value : _builder.add(HirUnary(.intToFloat, value));

  HirValue? _compare(String operator, HirValue left, HirValue right) {
    for (final relation in HirRelation.values) {
      if (relation.symbol == operator) {
        return _builder.add(HirCompare(relation, left, right));
      }
    }
    return null;
  }

  HirValue _boolean(
    AstNode node,
    String operator,
    HirValue left,
    HirValue right,
  ) {
    for (final known in HirBoolOperator.values) {
      if (known.symbol == operator) {
        return _builder.add(HirBoolBinary(known, left, right));
      }
    }
    return _compare(operator, left, right) ??
        _unsupported(node, 'operator $operator');
  }

  HirValue _integer(
    AstNode node,
    String operator,
    HirValue left,
    HirValue right,
  ) {
    for (final known in HirIntOperator.values) {
      if (known.symbol != operator) continue;
      if (known.isDivision || known.isShift) {
        final value = right is HirConst ? right.value as int : null;
        if (value == null) {
          _unsupported(node, 'operator $operator with a variable right side');
        }
        if (known.isDivision ? value == 0 : value < 0) {
          _unsupported(node, 'operator $operator throwing an exception');
        }
      }
      return _builder.add(HirIntBinary(known, left, right));
    }
    _unsupported(node, 'operator $operator');
  }

  HirValue _float(
    AstNode node,
    String operator,
    HirValue left,
    HirValue right,
  ) {
    for (final known in HirFloatOperator.values) {
      if (known.symbol == operator) {
        return _builder.add(HirFloatBinary(known, left, right));
      }
    }
    _unsupported(node, 'operator $operator on double');
  }
}
