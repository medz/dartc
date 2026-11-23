import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/hir.dart';

import 'builder.dart';
import 'calls.dart';
import 'checks.dart';
import 'scope.dart';
import 'types.dart';

/// Translates operators.
final class OperatorTranslator(
  final ProgramScope _scope,
  final FunctionBuilder _builder,
  final CallTranslator _calls,
) {
  late final _checked = CheckedOperations(_scope, _builder);

  Never _unsupported(AstNode node, String what) =>
      throw _builder.unit.unsupported(node, what);

  HirValue unary(PrefixExpression node, String operator, HirValue operand) {
    if (operand.type == .reference) {
      final element = node.element, class_ = classOf(node.operand.staticType);
      if (element == null || class_ == null) {
        _unsupported(node, 'this operator');
      }
      return _calls.invoke(node, operand, class_, element) ??
          _unsupported(node, 'operator $operator without a result');
    }
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
    if (left.type == .reference || right.type == .reference) {
      return _object(node, operator, left, right);
    }
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

  /// Applies an operator with an object or null on a side.
  HirValue _object(
    AstNode node,
    String operator,
    HirValue left,
    HirValue right,
  ) {
    final (element, type) = switch (node) {
      BinaryExpression(:final element, :final leftOperand) => (
        element,
        leftOperand.staticType,
      ),
      AssignmentExpression(:final element, :final readType) => (
        element,
        readType,
      ),
      PrefixExpression(:final element, :final readType) ||
      PostfixExpression(:final element, :final readType) => (element, readType),
      _ => (null, null),
    };
    if (operator == '==' || operator == '!=') {
      if (left.type != right.type) {
        _unsupported(node, 'operator $operator on these types');
      }
      final equal = _equal(node, element, classOf(type), left, right);
      return operator == '==' ? equal : _builder.add(HirUnary(.not, equal));
    }
    final class_ = classOf(type);
    if (left.type != .reference || element == null || class_ == null) {
      _unsupported(node, 'operator $operator on these types');
    }
    return _calls.invoke(node, left, class_, element, [right]) ??
        _unsupported(node, 'operator $operator without a result');
  }

  /// Null equals only null; otherwise the object on the left decides.
  HirValue _equal(
    AstNode node,
    MethodElement? element,
    ClassElement? class_,
    HirValue left,
    HirValue right,
  ) {
    HirValue identical() => _builder.add(HirCompare(.equal, left, right));
    // Where one side is the literal null, or has its type.
    if (left is HirNull || right is HirNull) return identical();
    if (element == null || class_ == null) return identical();
    final exit = _builder.join(node, .boolean);
    HirValue isNull(HirValue value) =>
        _builder.add(HirCompare(.equal, value, _builder.add(HirNull())));
    final either = _builder.add(
      HirBoolBinary(.or, isNull(left), isNull(right)),
    );
    _builder.branch(either, () => _builder.jump(exit, identical()), () {
      final result = _calls.invoke(node, left, class_, element, [right]);
      _builder.jump(exit, result);
    });
    return _builder.enter(exit)!;
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
      if (known.symbol == operator) {
        return _checked.integer(known, left, right);
      }
    }
    _unsupported(node, 'operator $operator');
  }

  HirValue _float(
    AstNode node,
    String operator,
    HirValue left,
    HirValue right,
  ) {
    if (operator == '~/') {
      return _checked.toInt(_builder.add(HirFloatBinary(.divide, left, right)));
    }
    for (final known in HirFloatOperator.values) {
      if (known.symbol == operator) {
        return _builder.add(HirFloatBinary(known, left, right));
      }
    }
    _unsupported(node, 'operator $operator on double');
  }
}
