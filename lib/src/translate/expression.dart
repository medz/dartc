import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';

import 'builder.dart';
import 'operators.dart';
import 'types.dart';

/// The kind of [node] in words, from its class name.
String describe(AstNode node) => node.runtimeType
    .toString()
    .replaceFirst('Impl', '')
    .replaceAllMapped(
      RegExp('(?<!^)[A-Z]'),
      (match) => ' ${match[0]!.toLowerCase()}',
    )
    .toLowerCase();

/// Translates the expressions of one function.
final class ExpressionTranslator(
  final FunctionLookup _functions,
  final FunctionBuilder _builder,
) {
  late final _operators = OperatorTranslator(_builder);

  Never _unsupported(AstNode node, String what) =>
      throw _builder.unit.unsupported(node, what);

  /// Evaluates [node] without using its value.
  void effect(Expression node) {
    final inner = node.unParenthesized;
    switch (inner) {
      case MethodInvocation():
        _call(inner);
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

  HirValue condition(Expression node) => value(node, wanted: .boolean);

  /// Evaluates [node].
  ///
  /// An expression that never completes stands for a value of type [wanted].
  HirValue value(Expression node, {HirType wanted = .integer}) {
    final inner = node.unParenthesized, type = inner.staticType;
    if (type is NeverType) {
      if (inner is! MethodInvocation) _unsupported(inner, describe(inner));
      _call(inner);
      return _builder.placeholder(wanted);
    }
    switch (inner) {
      case IntegerLiteral():
        return _integer(inner, negated: false);
      case DoubleLiteral(value: final Object constant) ||
          BooleanLiteral(value: final Object constant):
        return _builder.add(HirConst(constant));
      case SimpleIdentifier(:final element):
        return _identifier(inner, element);
      case PrefixedIdentifier(identifier: SimpleIdentifier(:final element)):
        return _identifier(inner, element);
      case PropertyAccess(propertyName: SimpleIdentifier(:final element)):
        return _constant(inner, element);
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
      case MethodInvocation():
        return _call(inner) ??
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
    return _constant(node, element);
  }

  /// The value of the constant variable that [element] refers to.
  HirValue _constant(Expression node, Element? element) {
    final variable = switch (element) {
      GetterElement(:final variable) => variable,
      VariableElement() => element,
      _ => null,
    };
    if (variable == null || !variable.isConst) {
      _unsupported(node, describe(node));
    }
    final constant = variable.computeConstantValue();
    final Object? value = switch (valueType(variable.type)) {
      .integer => constant?.toIntValue(),
      .float => constant?.toDoubleValue(),
      .boolean => constant?.toBoolValue(),
      null => _unsupported(node, 'a constant of type ${variable.type}'),
    };
    if (value == null) throw StateError('Unevaluated constant $node.');
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
    final variable = _variable(node, operand);
    final old = _builder.read(variable);
    final one = _builder.add(HirConst(1));
    final stepped = _operators.binary(node, operator[0], old, one);
    _builder.assign(variable, stepped);
    return after ? stepped : old;
  }

  HirValue _binary(BinaryExpression node) {
    final operator = node.operator.lexeme;
    switch (operator) {
      case '&&' || '||':
        return _shortCircuit(node, isAnd: operator == '&&');
      case '??':
        _unsupported(node, 'operator ??');
    }
    final left = value(node.leftOperand);
    final right = value(node.rightOperand, wanted: left.type!);
    return _operators.binary(node, operator, left, right);
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
      () => _builder.jump(exit, value(node.thenExpression, wanted: type)),
      () => _builder.jump(exit, value(node.elseExpression, wanted: type)),
    );
    return _builder.enter(exit)!;
  }

  /// The local variable or parameter that [node] assigns.
  VariableElement _variable(CompoundAssignmentExpression node, Expression to) {
    final element = node.writeElement;
    if (element is VariableElement && _builder.typeOf(element) != null) {
      return element;
    }
    _unsupported(to, 'assignment to ${describe(to)}');
  }

  HirValue _assignment(AssignmentExpression node) {
    final variable = _variable(node, node.leftHandSide);
    final type = _builder.typeOf(variable)!;
    final operator = node.operator.lexeme;
    if (operator == '??=') _unsupported(node, 'operator ??=');
    final HirValue result;
    if (operator == '=') {
      result = value(node.rightHandSide, wanted: type);
    } else {
      final old = _builder.read(variable);
      final right = value(node.rightHandSide, wanted: type);
      final name = operator.substring(0, operator.length - 1);
      result = _operators.binary(node, name, old, right);
    }
    _builder.assign(variable, result);
    return result;
  }

  /// Translates a call, returning its result if it has one.
  HirValue? _call(MethodInvocation node) {
    final target = node.target, element = node.methodName.element;
    if (target != null &&
            (target is! SimpleIdentifier || target.element is! PrefixElement) ||
        element is! TopLevelFunctionElement) {
      _unsupported(node, describe(node));
    }
    if (_isExit(element)) {
      final argument = node.argumentList.arguments.single.argumentExpression;
      final code = value(argument);
      _builder.end(HirExit(code));
      return null;
    }
    final function =
        _functions(element) ??
        _unsupported(node, 'calling ${element.displayName} of the SDK');
    final call = _builder.add(HirCall(function, _arguments(node, element)));
    if (element.returnType is NeverType) _builder.end(HirUnreachable());
    return call.type == null ? null : call;
  }

  static bool _isExit(TopLevelFunctionElement element) =>
      element.name == 'exit' && element.library.uri == Uri.parse('dart:io');

  /// Arguments in parameter order, evaluated in source order.
  List<HirValue> _arguments(
    MethodInvocation node,
    TopLevelFunctionElement element,
  ) {
    final parameters = element.formalParameters;
    final supplied = <FormalParameterElement, HirValue>{};
    for (final argument in node.argumentList.arguments) {
      final parameter = argument.correspondingParameter!;
      supplied[parameter] = value(
        argument.argumentExpression,
        wanted: valueType(parameter.type)!,
      );
    }
    return [
      for (final parameter in parameters)
        supplied[parameter] ?? _default(node, parameter),
    ];
  }

  HirValue _default(MethodInvocation node, FormalParameterElement parameter) {
    final constant = parameter.computeConstantValue();
    final Object? value = switch (valueType(parameter.type)) {
      .integer => constant?.toIntValue(),
      .float => constant?.toDoubleValue(),
      .boolean => constant?.toBoolValue(),
      null => null,
    };
    if (value == null) throw StateError('No default for ${parameter.name}.');
    return _builder.add(HirConst(value));
  }
}
