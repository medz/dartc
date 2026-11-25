import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';

import 'builder.dart';
import 'calls.dart';
import 'checks.dart';
import 'conversions.dart';
import 'dynamic_table.dart';
import 'dynamics.dart';
import 'members.dart';
import 'scope.dart';
import 'types.dart';

/// Translates operators.
final class OperatorTranslator(
  final ProgramScope _scope,
  final FunctionBuilder _builder,
  final CallTranslator _calls,
  final DynamicTranslator _dynamics,
  final Evaluator _evaluator,
) {
  late final _checked = CheckedOperations(_scope, _builder);
  late final _conversions = Conversions(_scope, _builder);

  Never _unsupported(AstNode node, String what) =>
      throw _builder.unit.unsupported(node, what);

  /// The operand [right] of the operator [element] of [leftType].
  (HirValue, DartType) operand(
    Expression right,
    HirValue left,
    MethodElement? element,
    DartType leftType,
  ) {
    final type = right.staticType!;
    final isOwn = isNumber(leftType) && !isExtensionMember(element);
    if (element == null || isOwn && type is! DynamicType) {
      return (_evaluator.value(right, placeholder: left.type!), type);
    }
    final declared = element.formalParameters.single.type;
    return (_evaluator.valueTo(right, declared), declared);
  }

  HirValue unary(PrefixExpression node, String operator, HirValue operand) {
    if (node.element case final element? when isExtensionMember(element)) {
      final type = _calls.receiverType(node.operand);
      return _calls.invoke(node, operand, type, element) ??
          _unsupported(node, 'operator $operator without a result');
    }
    if (operand.type == .reference) {
      final element = node.element, type = node.operand.staticType!;
      if (type is DynamicType) {
        final name = operator == '-' ? 'unary-' : operator;
        return _dynamics.operate(node, operand, name, const []);
      }
      if (operator == '-' && isNumber(type)) {
        return _number('numNegate', [operand]);
      }
      if (element == null || classOf(type) == null) {
        _unsupported(node, 'this operator');
      }
      return _calls.invoke(node, operand, type, element) ??
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

  /// Applies a binary operator, other than `&&`, `||` and `??`, to operands
  /// and their types.
  HirValue binary(
    AstNode node,
    String operator,
    (HirValue, DartType) leftOperand,
    (HirValue, DartType) rightOperand,
  ) {
    final (left, leftType) = leftOperand;
    final (right, rightType) = rightOperand;
    if (operator == '==' || operator == '!=') {
      final equal = _equal(node, leftOperand, rightOperand);
      return operator == '==' ? equal : _builder.add(HirUnary(.not, equal));
    }
    if (isBottom(leftType)) {
      _builder.end(HirUnreachable());
      return left;
    }
    if (leftType is DynamicType) {
      return _dynamics.operate(node, left, operator, [right]);
    }
    final element = switch (node) {
      BinaryExpression(:final element) ||
      AssignmentExpression(:final element) ||
      PrefixExpression(:final element) ||
      PostfixExpression(:final element) ||
      RelationalPattern(:final element) => element,
      _ => null,
    };
    if (element != null && isExtensionMember(element)) {
      return _apply(node, operator, left, leftType, element, right);
    }
    if (isNumber(leftType)) {
      if (left.type == .reference || right.type == .reference) {
        return _numbers(node, operator, left, right);
      }
      return _arithmetic(node, operator, left, right);
    }
    if (left.type == .boolean && right.type == .boolean) {
      return _boolean(node, operator, left, right);
    }
    if (left.type != .reference ||
        element == null ||
        classOf(leftType) == null) {
      _unsupported(node, 'operator $operator on these types');
    }
    return _apply(node, operator, left, leftType, element, right);
  }

  HirValue _apply(
    AstNode node,
    String operator,
    HirValue left,
    DartType type,
    MethodElement element,
    HirValue right,
  ) {
    final declared = element.formalParameters.single.type;
    final given = _conversions.coerce(right, valueType(declared)!);
    return _calls.invoke(node, left, type, element, [given]) ??
        _unsupported(node, 'operator $operator without a result');
  }

  HirValue _arithmetic(
    AstNode node,
    String operator,
    HirValue left,
    HirValue right,
  ) {
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

  /// Applies an operator to numbers of which one can be of any kind.
  HirValue _numbers(
    AstNode node,
    String operator,
    HirValue left,
    HirValue right,
  ) {
    final helper = numberHelpers[operator];
    if (helper == null) _unsupported(node, 'operator $operator on num');
    return _number(
      helper.name,
      helper.isSwapped ? [right, left] : [left, right],
    );
  }

  HirValue _number(String name, List<HirValue> operands) => _builder.call(
    HirCall(_scope.runtime(name), [
      for (final operand in operands) _conversions.coerce(operand, .reference),
    ]),
  )!;

  /// Null equals only null; otherwise the object on the left decides.
  HirValue _equal(
    AstNode node,
    (HirValue, DartType) leftOperand,
    (HirValue, DartType) rightOperand,
  ) {
    final (given, type) = leftOperand;
    final (other, _) = rightOperand;
    if (given.type != .reference && other.type != .reference) {
      return _equalPlain(given, other);
    }
    final left = _conversions.coerce(given, .reference);
    final right = _conversions.coerce(other, .reference);
    HirValue identical() => _builder.add(HirCompare(.equal, left, right));
    // Where one side is the literal null, or has its type.
    if (left is HirNull || right is HirNull) return identical();
    final element = node is BinaryExpression ? node.element : null;
    final object = _conversions.types.objectElement;
    final own = classOf(type) == null ? object.thisType : type;
    final method = element ?? object.getMethod('==')!;
    return _builder.choose(
      _builder.add(
        HirBoolBinary(
          .or,
          _conversions.isNull(left),
          _conversions.isNull(right),
        ),
      ),
      .boolean,
      identical,
      () => _calls.invoke(
        node,
        left,
        own,
        method,
        [right],
        const {},
        null,
        true,
      )!,
    );
  }

  HirValue _equalPlain(HirValue left, HirValue right) {
    if (left.type == right.type) {
      return _builder.add(HirCompare(.equal, left, right));
    }
    if (left.type == .boolean || right.type == .boolean) {
      return _builder.add(HirConst(false));
    }
    return _builder.add(HirCompare(.equal, _toFloat(left), _toFloat(right)));
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
