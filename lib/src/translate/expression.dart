import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';

import 'builder.dart';
import 'assignments.dart';
import 'calls.dart';
import 'chains.dart';
import 'checks.dart';
import 'closures.dart';
import 'constant.dart';
import 'conversions.dart';
import 'describe.dart';
import 'dynamics.dart';
import 'late_locals.dart';
import 'literals.dart';
import 'loops.dart';
import 'members.dart';
import 'operators.dart';
import 'patterns.dart';
import 'places.dart';
import 'records.dart';
import 'references.dart';
import 'scope.dart';
import 'statics.dart';
import 'texts.dart';
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
    _chains,
  );
  late final ClosureTranslator closures = ClosureTranslator(
    _scope,
    _builder,
    this,
    (target, node) => calls.object(target, node),
    (target) => calls.receiverType(target),
    (receiver, type, element, node) => calls.method(
      node,
      receiver,
      type,
      element,
      node.argumentList,
      types: node.typeArgumentTypes,
    ),
  );
  late final LateTranslator lates = LateTranslator(_scope, _builder);
  late final _chains = ChainTranslator(_builder);

  /// The targets of cascades, which are evaluated already.
  final _targets = <Expression, HirValue>{};
  late final _operators = OperatorTranslator(
    _scope,
    _builder,
    calls,
    _dynamics,
    this,
  );
  late final _dynamics = DynamicTranslator(_scope, _builder, this);
  late final _statics = StaticTranslator(_scope, _builder);
  late final _conversions = Conversions(_scope, _builder);
  late final PatternTranslator patterns = PatternTranslator(
    _scope,
    _builder,
    this,
    _operators,
    calls,
    _records,
    lates,
  );
  late final _records = RecordTranslator(_scope, _builder, this);
  late final _assignments = AssignmentTranslator(
    _builder,
    this,
    _places,
    _operators,
    _conversions,
  );
  late final _references = ReferenceTranslator(_scope, _builder);
  late final _texts = TextTranslator(_scope, _builder, this);
  late final LoopTranslator loops = LoopTranslator(
    _scope,
    _builder,
    this,
    calls,
    lates,
    (pattern, value, type) => patterns.destructure(pattern, value, type),
    (name, value, type) => _places.writeNamed(name, value, type),
  );
  late final _literals = LiteralTranslator(
    _scope,
    _builder,
    this,
    loops,
    patterns,
  );
  late final _places = PlaceTranslator(
    _builder,
    this,
    calls,
    _statics,
    _conversions,
    _dynamics,
    lates,
    _chains,
  );

  Never _unsupported(AstNode node, String what) =>
      throw _builder.unit.unsupported(node, what);

  @override
  void effect(Expression node) {
    final inner = node.unParenthesized;
    if (_chains.isWhole(inner)) {
      _chains.translate(inner, null, () {
        effect(inner);
        return null;
      });
      return;
    }
    switch (inner) {
      case MethodInvocation():
        calls.invocation(inner);
      case DotShorthandInvocation():
        calls.shorthand(inner);
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
  HirValue valueAsObject(Expression node, DartType type) =>
      _conversions.coerce(valueTo(node, type), .reference);

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
    if (_targets[inner] case final value?) return value;
    if (_chains.isWhole(inner)) {
      final result = valueType(_resultType(inner))!;
      return _chains.translate(
        inner,
        result,
        () => _conversions.coerce(_value(inner, result), result),
      )!;
    }
    if (isNever(type)) {
      _never(inner);
      return _builder.placeholder(placeholder);
    }
    switch (inner) {
      case Literal():
        return _literal(inner);
      case TypeLiteral(type: TypeAnnotation(:final DartType type)):
        return _references.type(inner, type);
      case ThisExpression():
        return _builder.receiver ?? _unsupported(inner, 'this here');
      case SimpleIdentifier(:final element):
        return _identifier(inner, element);
      case PrefixedIdentifier() || PropertyAccess():
        return _access(inner);
      case PrefixExpression():
        return _prefix(inner);
      case PostfixExpression(:final operator, :final operand):
        if (operator.lexeme == '!') return _notNull(operand);
        return _assignments.step(inner, operand, operator.lexeme, after: false);
      case BinaryExpression():
        return _binary(inner);
      case ConditionalExpression():
        return _conditional(inner);
      case AssignmentExpression():
        return _assignments.assign(inner);
      case FunctionExpression():
        return closures.create(inner);
      case FunctionExpressionInvocation():
        return closures.invocation(inner) ??
            _unsupported(inner, 'using a value of type $type');
      case ExtensionOverride(:final argumentList):
        return value(argumentList.arguments.single.argumentExpression);
      case FunctionReference():
        return _references.function(inner, value);
      case ConstructorReference(:final constructorName):
        return _references.constructor(inner, constructorName);
      case ImplicitCallReference(:final expression, :final element):
        if (element == null) _unsupported(inner, describe(inner));
        final method = calls.tearOff(
          inner,
          calls.object(expression, inner),
          expression.staticType,
          element,
        );
        return _references.withTypes(
          inner,
          method,
          inner.typeArgumentTypes,
          type!,
        );
      case IsExpression():
        return _isExpression(inner);
      case AsExpression():
        return _asExpression(inner);
      case InstanceCreationExpression() ||
          DotShorthandConstructorInvocation() ||
          DotShorthandInvocation() ||
          DotShorthandPropertyAccess() ||
          MethodInvocation():
        return _invocation(inner, placeholder);
      case IndexExpression():
        return calls.index(inner);
      case CascadeExpression():
        return _cascade(inner);
      case PatternAssignment(:final pattern, :final expression):
        final result = value(expression);
        patterns.destructure(pattern, result, expression.staticType!);
        return result;
      case SwitchExpression():
        return patterns.switchExpression(inner, _resultType(inner));
      default:
        _unsupported(inner, describe(inner));
    }
  }

  /// Calls something by its name, or creates an object.
  HirValue _invocation(Expression inner, HirType placeholder) {
    HirValue result(HirValue? given, Element? element) =>
        given ??
        _neverResult(element, placeholder) ??
        _unsupported(inner, 'using a value of type ${inner.staticType}');
    switch (inner) {
      case InstanceCreationExpression(
            constructorName: ConstructorName(:final element),
            :final argumentList,
            :final isConst,
          ) ||
          DotShorthandConstructorInvocation(
            :final element,
            :final argumentList,
            :final isConst,
          ):
        return calls.creation(inner, element, argumentList, isConst: isConst);
      case DotShorthandInvocation(:final memberName):
        return result(calls.shorthand(inner), memberName.element);
      case DotShorthandPropertyAccess(
        propertyName: SimpleIdentifier(:final element),
      ):
        return _statics.read(inner, element);
      case MethodInvocation(:final methodName):
        return result(calls.invocation(inner), methodName.element);
      default:
        _unsupported(inner, describe(inner));
    }
  }

  HirValue _literal(Literal inner) {
    switch (inner) {
      case IntegerLiteral():
        return _integer(inner, isNegated: false);
      case DoubleLiteral(value: final Object constant) ||
          BooleanLiteral(value: final Object constant):
        return _builder.add(HirConst(constant));
      case NullLiteral():
        return _builder.add(HirNull());
      case StringLiteral():
        return _texts.string(inner);
      case SymbolLiteral():
        final value = inner.computeConstantValue()?.value;
        return _builder.add(
          _scope.constantOf(.reference, value) ??
              _unsupported(inner, describe(inner)),
        );
      case TypedLiteral(isConst: true):
        final found = _scope.constantOf(
          .reference,
          inner.computeConstantValue()?.value,
        );
        return _builder.add(
          found ??
              _unsupported(inner, 'a constant of type ${inner.staticType}'),
        );
      case RecordLiteral(isConst: true):
        final found = _scope.constantOf(
          .reference,
          inner.computeConstantValue()?.value,
        );
        return _builder.add(found ?? _unsupported(inner, describe(inner)));
      case RecordLiteral():
        return _records.create(inner);
      case ListLiteral():
        return _literals.list(inner);
      case SetOrMapLiteral():
        return _literals.setOrMap(inner);
    }
  }

  /// What stands for the result of calling [element], if that never returns.
  ///
  /// The call itself is of another type where it can be skipped.
  HirValue? _neverResult(Element? element, HirType placeholder) =>
      element is ExecutableElement && isNever(element.returnType)
      ? _builder.placeholder(placeholder)
      : null;

  HirValue _cascade(CascadeExpression node) {
    final target = node.target.unParenthesized;
    final result = value(target);
    void sections() {
      _targets[target] = result;
      node.cascadeSections.forEach(effect);
      _targets.remove(target);
    }

    if (!node.isNullAware || result.type != .reference) {
      sections();
      return result;
    }
    final exit = _builder.join(node);
    _builder.branch(_conversions.isNull(result), () => _builder.jump(exit), () {
      sections();
      _builder.jump(exit);
    });
    _builder.enter(exit);
    return result;
  }

  /// Evaluates [inner], which gives no value.
  void _never(Expression inner) {
    switch (inner) {
      case MethodInvocation():
        calls.invocation(inner);
      case DotShorthandInvocation():
        calls.shorthand(inner);
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
  }

  /// Reads a field of a record, if [inner] is one.
  HirValue? _recordField(Expression inner) {
    final (target, name) = switch (inner) {
      PrefixedIdentifier(:final prefix, :final identifier) => (
        prefix,
        identifier.name,
      ),
      PropertyAccess(:final realTarget, :final propertyName) => (
        realTarget,
        propertyName.name,
      ),
      _ => (inner, ''),
    };
    final type = target.staticType;
    if (type == null || fieldIndex(type, name) == null) return null;
    return _records.field(calls.object(target, inner), type, name);
  }

  /// Reads a property, or what a library or class declares.
  HirValue _access(Expression inner) {
    if (_recordField(inner) case final found?) return found;
    switch (inner) {
      case PrefixedIdentifier(:final prefix, :final identifier)
          when prefix.staticType is DynamicType:
        return _dynamics.get(inner, value(prefix), identifier.name);
      case PropertyAccess(:final realTarget, :final propertyName)
          when realTarget.staticType is DynamicType:
        final object = value(realTarget);
        _chains.check(inner, object);
        return _dynamics.get(inner, object, propertyName.name);
      case PrefixedIdentifier(
            prefix: Expression(staticType: FunctionType()) &&
                final Expression function,
            identifier: SimpleIdentifier(name: 'call'),
          ) ||
          PropertyAccess(
            target: Expression(staticType: FunctionType()) &&
                final Expression function,
            propertyName: SimpleIdentifier(name: 'call'),
          ):
        final result = value(function);
        _chains.check(inner, result);
        return result;
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
      default:
        _unsupported(inner, describe(inner));
    }
  }

  void _throw(Expression expression) {
    final value = valueAs(expression, .reference);
    _builder.call(HirCall(_scope.runtime('markThrown'), [value]));
    _builder.raise(value, _builder.add(_scope.trace));
  }

  HirValue _notNull(Expression operand) =>
      CheckedOperations(_scope, _builder).notNull(value(operand));

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
    if (ReferenceTranslator.typeNamed(element) case final type?) {
      return _references.type(node, type);
    }
    if (element != null &&
        _builder.typeOf(element) != null &&
        !(element is VariableElement && element.isConst)) {
      return lates.read(element) ?? _builder.read(element);
    }
    return isInstanceMember(element)
        ? calls.property(node, null, element!)
        : _statics.read(node, element);
  }

  HirValue _prefix(PrefixExpression node) {
    final operator = node.operator.lexeme, operand = node.operand;
    switch (operator) {
      case '++' || '--':
        return _assignments.step(node, operand, operator, after: true);
      case '!':
        return _operators.unary(node, operator, condition(operand));
      case '-' when operand is IntegerLiteral:
        return _integer(operand, isNegated: true);
      default:
        return _operators.unary(node, operator, value(operand));
    }
  }

  HirValue _binary(BinaryExpression node) {
    final operator = node.operator.lexeme;
    switch (operator) {
      case '&&' || '||':
        return _shortCircuit(node, isAnd: operator == '&&');
      case '??':
        final type = _resultType(node);
        return _conversions.ifNull(
          node,
          valueType(type)!,
          value(node.leftOperand),
          () => valueTo(node.rightOperand, type),
        );
    }
    final target = node.leftOperand;
    final type = calls.receiverType(target)!;
    if (target is SuperExpression) {
      final element = node.element ?? _unsupported(node, describe(node));
      final type = element.formalParameters.single.type;
      final right = valueTo(node.rightOperand, type);
      final result = calls.superMember(node, element, [right])!;
      return operator == '!=' ? _builder.add(HirUnary(.not, result)) : result;
    }
    final left = value(target);
    final (right, rightType) = _rightOperand(node, left, type);
    return _operators.binary(node, operator, (left, type), (right, rightType));
  }

  /// Operators of classes convert their operand as calls do.
  (HirValue, DartType) _rightOperand(
    BinaryExpression node,
    HirValue left,
    DartType leftType,
  ) {
    final right = node.rightOperand, operator = node.operator.lexeme;
    final isEquality = operator == '==' || operator == '!=';
    return _operators.operand(
      right,
      left,
      isEquality ? null : node.element,
      leftType,
    );
  }

  /// Whether the constant [node] equals [value].
  HirValue equal(Expression node, (HirValue, DartType) value) => _operators
      .binary(node, '==', (this.value(node), node.staticType!), value);

  DartType _resultType(Expression node) {
    final type = node.staticType!;
    return valueType(type) != null
        ? type
        : _unsupported(node, 'a value of type $type');
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
}
