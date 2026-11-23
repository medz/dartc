import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';

import 'builder.dart';
import 'calls.dart';
import 'constant.dart';
import 'describe.dart';
import 'members.dart';
import 'operators.dart';
import 'places.dart';
import 'scope.dart';
import 'types.dart';

/// Translates the expressions of one function.
final class ExpressionTranslator(
  final ProgramScope _scope,
  final FunctionBuilder _builder,
) implements Evaluator {
  late final calls = CallTranslator(_scope, _builder, this);
  late final _operators = OperatorTranslator(_builder, calls);
  late final _places = PlaceTranslator(_builder, this, calls);

  Never _unsupported(AstNode node, String what) =>
      throw _builder.unit.unsupported(node, what);

  /// Evaluates [node] without using its value.
  void effect(Expression node) {
    final inner = node.unParenthesized;
    switch (inner) {
      case MethodInvocation():
        calls.invocation(inner, isUsed: false);
      case ConditionalExpression(:final DartType staticType)
          when hasNoResult(staticType):
        final exit = _builder.join(inner);
        void run(Expression part) {
          effect(part);
          _builder.jump(exit);
        }

        _builder.branch(
          condition(inner.condition),
          () => run(inner.thenExpression),
          () => run(inner.elseExpression),
        );
        _builder.enter(exit);
      default:
        value(inner);
    }
  }

  HirValue condition(Expression node) => valueAs(node, .boolean);

  @override
  HirValue valueAs(Expression node, HirType type) {
    final result = value(node, placeholder: type);
    if (result.type == type) return result;
    if (type != .reference) {
      _unsupported(node, 'using ${node.staticType} as ${type.dartName}');
    }
    _unsupported(node, 'using ${result.type!.dartName} as an object');
  }

  @override
  HirValue value(Expression node, {HirType placeholder = .integer}) {
    final inner = node.unParenthesized, type = inner.staticType;
    if (type is NeverType) {
      if (inner is! MethodInvocation) _unsupported(inner, describe(inner));
      calls.invocation(inner, isUsed: false);
      return _builder.placeholder(placeholder);
    }
    switch (inner) {
      case IntegerLiteral():
        return _integer(inner, negated: false);
      case DoubleLiteral(value: final Object constant) ||
          BooleanLiteral(value: final Object constant):
        return _builder.add(HirConst(constant));
      case NullLiteral():
        return _builder.add(HirNull());
      case ThisExpression():
        return _builder.receiver ?? _unsupported(inner, 'this here');
      case SimpleIdentifier(:final element):
        return _identifier(inner, element);
      case PrefixedIdentifier(
        :final prefix,
        identifier: SimpleIdentifier(:final element),
      ):
        return isInstanceMember(element)
            ? calls.property(inner, prefix, element!)
            : _constant(inner, element);
      case PropertyAccess(
        :final realTarget,
        propertyName: SimpleIdentifier(:final element),
      ):
        return isInstanceMember(element)
            ? calls.property(inner, realTarget, element!)
            : _constant(inner, element);
      case PrefixExpression():
        return _prefix(inner);
      case PostfixExpression(:final operator, :final operand):
        if (operator.lexeme == '!') _unsupported(inner, 'operator !');
        return _step(inner, operand, operator.lexeme, after: false);
      case BinaryExpression():
        return _binary(inner);
      case ConditionalExpression():
        return _conditional(inner);
      case AssignmentExpression():
        return _assignment(inner);
      case InstanceCreationExpression():
        return calls.creation(inner);
      case IndexExpression():
        return calls.index(inner);
      case MethodInvocation():
        return calls.invocation(inner, isUsed: true) ??
            _unsupported(inner, 'using a value of type $type');
      default:
        _unsupported(inner, describe(inner));
    }
  }

  HirValue _integer(IntegerLiteral node, {required bool negated}) {
    final type = valueType(node.staticType!);
    final Object? value = switch (type) {
      .integer => node.parseIntValue(negated: negated),
      .float => node.parseDoubleValue(negated: negated),
      _ => _unsupported(node, 'a literal of type ${node.staticType}'),
    };
    if (value == null) throw StateError('Unchecked literal $node.');
    return _builder.add(HirConst(value));
  }

  HirValue _identifier(Expression node, Element? element) {
    if (element is VariableElement &&
        _builder.typeOf(element) != null &&
        !element.isConst) {
      return _builder.read(element);
    }
    return isInstanceMember(element)
        ? calls.property(node, null, element!)
        : _constant(node, element);
  }

  /// The value of the constant variable that [element] refers to.
  HirValue _constant(Expression node, Element? element) {
    final variable = constantVariable(element);
    if (variable == null) _unsupported(node, describe(node));
    final value =
        constantNumber(variable) ??
        _unsupported(node, 'a constant of type ${variable.type}');
    return _builder.add(HirConst(value));
  }

  HirValue _prefix(PrefixExpression node) {
    final operator = node.operator.lexeme, operand = node.operand;
    switch (operator) {
      case '++' || '--':
        return _step(node, operand, operator, after: true);
      case '-' when operand is IntegerLiteral:
        return _integer(operand, negated: true);
      default:
        return _operators.unary(node, operator, value(operand));
    }
  }

  /// Adds or subtracts 1, giving the value before or after.
  HirValue _step(
    CompoundAssignmentExpression node,
    Expression operand,
    String operator, {
    required bool after,
  }) {
    final place = _places.place(node, operand);
    final old = _places.read(place);
    final one = _builder.add(HirConst(1));
    final stepped = _operators.binary(node, operator[0], old, one);
    _checkType(node, stepped, place);
    _places.write(place, stepped);
    return after ? stepped : old;
  }

  void _checkType(Expression node, HirValue value, Place place) {
    if (value.type == place.type) return;
    _unsupported(node, 'assigning a value of another type');
  }

  HirValue _binary(BinaryExpression node) {
    final operator = node.operator.lexeme;
    switch (operator) {
      case '&&' || '||':
        return _shortCircuit(node, isAnd: operator == '&&');
      case '??':
        return _ifNull(
          node,
          valueAs(node.leftOperand, .reference),
          () => valueAs(node.rightOperand, .reference),
        );
    }
    final target = node.leftOperand;
    if (target is SuperExpression) {
      final element = node.element ?? _unsupported(node, describe(node));
      final type = valueType(element.formalParameters.single.type);
      final right = valueAs(
        node.rightOperand,
        type ?? _unsupported(node, describe(node)),
      );
      final result = calls.superMember(node, element, [right])!;
      return operator == '!=' ? _builder.add(HirUnary(.not, result)) : result;
    }
    final left = value(target);
    final right = _rightOperand(node, left);
    return _operators.binary(node, operator, left, right);
  }

  /// Operators of classes convert their operand as calls do.
  HirValue _rightOperand(BinaryExpression node, HirValue left) {
    final element = node.element;
    if (left.type == .reference &&
        element != null &&
        node.operator.lexeme != '==' &&
        node.operator.lexeme != '!=') {
      final type = valueType(element.formalParameters.single.type);
      if (type != null) return valueAs(node.rightOperand, type);
    }
    return value(node.rightOperand, placeholder: left.type!);
  }

  /// [left], or what [right] gives if that is null.
  HirValue _ifNull(Expression node, HirValue left, HirValue Function() right) {
    final exit = _builder.join(node, .reference);
    final isNull = _builder.add(
      HirCompare(.equal, left, _builder.add(HirNull())),
    );
    _builder.branch(
      isNull,
      () => _builder.jump(exit, right()),
      () => _builder.jump(exit, left),
    );
    return _builder.enter(exit)!;
  }

  HirValue _shortCircuit(BinaryExpression node, {required bool isAnd}) {
    final exit = _builder.join(node, .boolean);
    void decided() => _builder.jump(exit, _builder.add(HirConst(!isAnd)));
    void undecided() => _builder.jump(exit, condition(node.rightOperand));
    _builder.branch(
      condition(node.leftOperand),
      isAnd ? undecided : decided,
      isAnd ? decided : undecided,
    );
    return _builder.enter(exit)!;
  }

  HirValue _conditional(ConditionalExpression node) {
    final type =
        valueType(node.staticType!) ??
        _unsupported(node, 'a value of type ${node.staticType}');
    final exit = _builder.join(node, type);
    _builder.branch(
      condition(node.condition),
      () => _builder.jump(exit, valueAs(node.thenExpression, type)),
      () => _builder.jump(exit, valueAs(node.elseExpression, type)),
    );
    return _builder.enter(exit)!;
  }

  HirValue _assignment(AssignmentExpression node) {
    final place = _places.place(node, node.leftHandSide);
    final operator = node.operator.lexeme;
    if (operator == '=') {
      final result = valueAs(node.rightHandSide, place.type);
      _places.write(place, result);
      return result;
    }
    final old = _places.read(place);
    if (operator == '??=') {
      if (old.type != .reference) _unsupported(node, 'operator ??=');
      return _ifNull(node, old, () {
        final result = valueAs(node.rightHandSide, .reference);
        _places.write(place, result);
        return result;
      });
    }
    final element = node.element;
    final declared = old.type == .reference && element != null
        ? valueType(element.formalParameters.single.type)
        : null;
    final right = declared == null
        ? value(node.rightHandSide, placeholder: old.type!)
        : valueAs(node.rightHandSide, declared);
    final name = operator.substring(0, operator.length - 1);
    final result = _operators.binary(node, name, old, right);
    _checkType(node, result, place);
    _places.write(place, result);
    return result;
  }
}
