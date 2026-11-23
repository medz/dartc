import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';

import 'builder.dart';
import 'calls.dart';
import 'checks.dart';
import 'closures.dart';
import 'constant.dart';
import 'conversions.dart';
import 'describe.dart';
import 'members.dart';
import 'operators.dart';
import 'places.dart';
import 'scope.dart';
import 'statics.dart';
import 'types.dart';

/// Translates the expressions of one function.
final class ExpressionTranslator(
  final ProgramScope _scope,
  final FunctionBuilder _builder,
) implements Evaluator {
  late final CallTranslator calls = CallTranslator(
    _scope,
    _builder,
    this,
    closures,
  );
  late final ClosureTranslator closures = ClosureTranslator(
    _scope,
    _builder,
    this,
    (node, receiver, class_, element, list) =>
        calls.method(node, receiver, class_, element, list),
  );
  late final _operators = OperatorTranslator(_scope, _builder, calls);
  late final _statics = StaticTranslator(_scope, _builder);
  late final _conversions = Conversions(_scope, _builder);
  late final _places = PlaceTranslator(
    _builder,
    this,
    calls,
    _statics,
    _conversions,
  );

  Never _unsupported(AstNode node, String what) =>
      throw _builder.unit.unsupported(node, what);

  /// Evaluates [node] without using its value.
  void effect(Expression node) {
    final inner = node.unParenthesized;
    switch (inner) {
      case MethodInvocation():
        calls.invocation(inner, isUsed: false);
      case FunctionExpressionInvocation():
        closures.invocation(inner);
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

  HirValue condition(Expression node) =>
      valueTo(node, _conversions.types.boolType);

  @override
  HirValue valueTo(Expression node, DartType type) {
    final representation = valueType(type);
    if (representation == null) _unsupported(node, 'a value of type $type');
    final result = value(node, placeholder: representation);
    final from = node.staticType!;
    if (from is! DynamicType) {
      return _conversions.coerce(result, representation);
    }
    return _conversions.cast(result, from, type) ??
        _unsupported(node, 'testing for $type');
  }

  @override
  HirValue valueAs(Expression node, HirType type) =>
      _conversions.coerce(value(node, placeholder: type), type);

  @override
  HirValue value(Expression node, {HirType placeholder = .integer}) {
    final result = _value(node, placeholder);
    final type = node.staticType;
    if (type == null || isNever(type)) return result;
    final representation = valueType(type);
    return representation == null
        ? result
        : _conversions.coerce(result, representation);
  }

  HirValue _value(Expression node, HirType placeholder) {
    final inner = node.unParenthesized, type = inner.staticType;
    if (isNever(type)) {
      switch (inner) {
        case MethodInvocation():
          calls.invocation(inner, isUsed: false);
        case ThrowExpression(:final expression):
          _throw(expression);
        case FunctionExpressionInvocation():
          closures.invocation(inner);
        case RethrowExpression():
          final (exception, trace) = _builder.caught.last;
          _builder.raise(exception, trace);
        default:
          _unsupported(inner, describe(inner));
      }
      return _builder.placeholder(placeholder);
    }
    switch (inner) {
      case IntegerLiteral():
        return _integer(inner, isNegated: false);
      case DoubleLiteral(value: final Object constant) ||
          BooleanLiteral(value: final Object constant):
        return _builder.add(HirConst(constant));
      case NullLiteral():
        return _builder.add(HirNull());
      case ThisExpression():
        return _builder.receiver ?? _unsupported(inner, 'this here');
      case SimpleIdentifier(:final element):
        return _identifier(inner, element);
      case PrefixedIdentifier(:final prefix)
          when prefix.staticType is DynamicType:
        _unsupported(prefix, usingDynamic);
      case PropertyAccess(:final realTarget)
          when realTarget.staticType is DynamicType:
        _unsupported(realTarget, usingDynamic);
      case PrefixedIdentifier(
            prefix: Expression(staticType: FunctionType()) &&
                final Expression function,
            identifier: SimpleIdentifier(name: 'call'),
          ) ||
          PropertyAccess(
            target: Expression(staticType: FunctionType()) &&
                final Expression function,
            propertyName: SimpleIdentifier(name: 'call'),
            isNullAware: false,
          ):
        return value(function);
      case PrefixedIdentifier(
        :final prefix,
        identifier: SimpleIdentifier(:final element),
      ):
        return isInstanceMember(element)
            ? calls.property(inner, prefix, element!)
            : _statics.read(inner, element);
      case PropertyAccess(
        :final realTarget,
        propertyName: SimpleIdentifier(:final element),
      ):
        return isInstanceMember(element)
            ? calls.property(inner, realTarget, element!)
            : _statics.read(inner, element);
      case PrefixExpression():
        return _prefix(inner);
      case PostfixExpression(:final operator, :final operand):
        if (operator.lexeme == '!') return _notNull(inner, operand);
        return _step(inner, operand, operator.lexeme, after: false);
      case BinaryExpression():
        return _binary(inner);
      case ConditionalExpression():
        return _conditional(inner);
      case AssignmentExpression():
        return _assignment(inner);
      case FunctionExpression():
        return closures.create(inner);
      case FunctionExpressionInvocation():
        return closures.invocation(inner) ??
            _unsupported(inner, 'using a value of type $type');
      case ConstructorReference(:final constructorName):
        return _constructor(inner, constructorName);
      case ImplicitCallReference(:final expression, :final element):
        final class_ = classOf(expression.staticType);
        if (class_ == null || element == null) {
          _unsupported(inner, describe(inner));
        }
        return calls.tearOff(
          inner,
          valueAs(expression, .reference),
          class_,
          element,
        );
      case IsExpression():
        return _isExpression(inner);
      case AsExpression():
        return _asExpression(inner);
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

  void _throw(Expression expression) {
    final value = valueAs(expression, .reference);
    final class_ = classOf(expression.staticType);
    if (class_ == null) {
      _unsupported(expression, 'throwing ${expression.staticType}');
    }
    _scope.addThrown(class_);
    _builder.raise(value, _builder.create(_scope.traceClass));
  }

  HirValue _notNull(PostfixExpression node, Expression operand) {
    if (CallTranslator.hasNullAware(operand)) {
      _unsupported(node, 'null-aware chains');
    }
    return CheckedOperations(_scope, _builder).notNull(value(operand));
  }

  HirValue _constructor(Expression node, ConstructorName name) {
    final element = name.element;
    final object = element == null ? null : _scope.functionObject(element);
    if (object == null || classOf(element!.returnType) == null) {
      _unsupported(node, describe(node));
    }
    return _builder.add(HirStatic(object));
  }

  HirValue _isExpression(IsExpression node) {
    final type = node.type.type!;
    final result =
        _conversions.isInstance(value(node.expression), type) ??
        _unsupported(node.type, 'testing for $type');
    return node.notOperator == null
        ? result
        : _builder.add(HirUnary(.not, result));
  }

  HirValue _asExpression(AsExpression node) {
    final type = node.type.type!, from = node.expression.staticType!;
    return _conversions.cast(
          value(node.expression, placeholder: .reference),
          from,
          type,
          ending: ' in type cast',
        ) ??
        _unsupported(node.type, 'testing for $type');
  }

  HirValue _integer(IntegerLiteral node, {required bool isNegated}) =>
      _builder.add(
        HirConst(
          integerLiteral(node, isNegated: isNegated) ??
              _unsupported(node, 'a literal of type ${node.staticType}'),
        ),
      );

  HirValue _identifier(Expression node, Element? element) {
    if (element != null &&
        _builder.typeOf(element) != null &&
        !(element is VariableElement && element.isConst)) {
      return _builder.read(element);
    }
    return isInstanceMember(element)
        ? calls.property(node, null, element!)
        : _statics.read(node, element);
  }

  HirValue _prefix(PrefixExpression node) {
    final operator = node.operator.lexeme, operand = node.operand;
    switch (operator) {
      case '++' || '--':
        return _step(node, operand, operator, after: true);
      case '-' when operand is IntegerLiteral:
        return _integer(operand, isNegated: true);
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
    final stepped = _operators.binary(
      node,
      operator[0],
      (old, node.readType!),
      (one, _conversions.types.intType),
    );
    _places.write(place, stepped);
    return after ? stepped : old;
  }

  HirValue _binary(BinaryExpression node) {
    final operator = node.operator.lexeme;
    switch (operator) {
      case '&&' || '||':
        return _shortCircuit(node, isAnd: operator == '&&');
      case '??':
        final type = _resultType(node);
        return _ifNull(
          node,
          value(node.leftOperand),
          () => valueTo(node.rightOperand, type),
        );
    }
    final target = node.leftOperand;
    if (target is SuperExpression) {
      final element = node.element ?? _unsupported(node, describe(node));
      final type = element.formalParameters.single.type;
      final right = valueTo(node.rightOperand, type);
      final result = calls.superMember(node, element, [right])!;
      return operator == '!=' ? _builder.add(HirUnary(.not, result)) : result;
    }
    final left = value(target);
    final (right, rightType) = _rightOperand(node, left);
    return _operators.binary(
      node,
      operator,
      (left, target.staticType!),
      (right, rightType),
    );
  }

  /// Operators of classes convert their operand as calls do.
  (HirValue, DartType) _rightOperand(BinaryExpression node, HirValue left) {
    final right = node.rightOperand, operator = node.operator.lexeme;
    final isEquality = operator == '==' || operator == '!=';
    return _operand(
      right,
      left,
      isEquality ? null : node.element,
      node.leftOperand.staticType!,
    );
  }

  /// The operand [right] of the operator [element] of [leftType].
  (HirValue, DartType) _operand(
    Expression right,
    HirValue left,
    MethodElement? element,
    DartType leftType,
  ) {
    final type = right.staticType!;
    if (element == null || isNumber(leftType) && type is! DynamicType) {
      return (value(right, placeholder: left.type!), type);
    }
    final declared = element.formalParameters.single.type;
    return (valueTo(right, declared), declared);
  }

  DartType _resultType(Expression node) {
    final type = node.staticType!;
    return valueType(type) != null
        ? type
        : _unsupported(node, 'a value of type $type');
  }

  /// [left], or what [right] gives if that is null.
  HirValue _ifNull(Expression node, HirValue left, HirValue Function() right) {
    final type = valueType(_resultType(node))!;
    if (left.type != .reference) return _conversions.coerce(left, type);
    final exit = _builder.join(node, type);
    _builder.branch(
      _conversions.isNull(left),
      () => _builder.jump(exit, right()),
      () => _builder.jump(exit, _conversions.coerce(left, type)),
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
    final type = _resultType(node);
    final exit = _builder.join(node, valueType(type));
    _builder.branch(
      condition(node.condition),
      () => _builder.jump(exit, valueTo(node.thenExpression, type)),
      () => _builder.jump(exit, valueTo(node.elseExpression, type)),
    );
    return _builder.enter(exit)!;
  }

  HirValue _assignment(AssignmentExpression node) {
    final place = _places.place(node, node.leftHandSide);
    final operator = node.operator.lexeme;
    if (operator == '=') {
      return _assign(place, node.rightHandSide);
    }
    final old = _places.read(place);
    if (operator == '??=') {
      return _ifNull(node, old, () {
        final result = _assign(place, node.rightHandSide);
        return _conversions.coerce(result, valueType(_resultType(node))!);
      });
    }
    final readType = node.readType!;
    final (right, rightType) = _operand(
      node.rightHandSide,
      old,
      node.element,
      readType,
    );
    final result = _operators.binary(
      node,
      operator.substring(0, operator.length - 1),
      (old, readType),
      (right, rightType),
    );
    _places.write(place, result);
    return result;
  }

  /// Assigns [node], whose own value is the result.
  HirValue _assign(Place place, Expression node) {
    final type = node.staticType!;
    final result = value(node, placeholder: valueType(place.type)!);
    if (type is! DynamicType) {
      _places.write(place, result);
      return result;
    }
    final checked =
        _conversions.cast(result, type, place.type) ??
        _unsupported(node, 'testing for ${place.type}');
    _places.write(place, checked);
    return checked;
  }
}
