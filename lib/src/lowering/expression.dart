import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/ast/token.dart' show Token;
import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/ir.dart';

import 'bindings.dart';
import 'function_context.dart';

/// Emits [expression] and leaves [context] at its normal continuation block.
Value lowerExpression(FunctionContext context, ast.Expression expression) {
  final unit = context.unit;
  switch (expression) {
    case ast.BooleanLiteral(:final value):
      return Constant.boolean(value);
    case ast.IntegerLiteral():
      return _integerLiteral(context, expression, expression, negated: false);
    case ast.PrefixExpression(
      operator: Token(type: .MINUS),
      operand: final ast.IntegerLiteral literal,
    ):
      return _integerLiteral(context, expression, literal, negated: true);
    case ast.DoubleLiteral(:final value):
      return Constant.floating(value);
    case ast.PrefixExpression(
      operator: Token(type: .MINUS),
      operand: ast.DoubleLiteral(:final value),
    ):
      return Constant.floating(-value);
    case ast.NullLiteral():
      return const Constant.nullValue();
    case ast.StringLiteral(stringValue: final value?):
      return Constant.string(value);
    case ast.ParenthesizedExpression(:final expression):
      return lowerExpression(context, expression);
    case ast.ConditionalExpression(
      :final condition,
      :final thenExpression,
      :final elseExpression,
    ):
      return context.branch(
        lowerExpression(context, condition),
        () => lowerExpression(context, thenExpression),
        () => lowerExpression(context, elseExpression),
        valueType(expression.staticType!, unit, expression),
      )!;
    case ast.SimpleIdentifier(element: final VariableElement variable)
        when context.locals.containsKey(variable):
      return context.locals[variable]!;
    case ast.Identifier(
          element: GetterElement(
            variable: final TopLevelVariableElement variable,
          ),
        )
        when variable.isConst:
      if (expression is ast.PrefixedIdentifier && expression.isDeferred) {
        unsupported(unit, expression, 'deferred constant');
      }
      return scalarConstant(variable, unit, expression);
    case ast.CompoundAssignmentExpression():
      return _updateLocal(context, expression);
    case ast.MethodInvocation(
      methodName: ast.SimpleIdentifier(
        element: final TopLevelFunctionElement callee,
      ),
    ):
      if (expression.target case final receiver?) {
        final prefix = receiver is ast.SimpleIdentifier
            ? receiver.element
            : null;
        if (prefix is! PrefixElement ||
            prefix.imports.any((i) => i.prefix?.isDeferred == true)) {
          unsupported(unit, expression, 'call receiver');
        }
      }
      final target = context.bindings.target(callee, unit, expression);
      final args = context.bindings.arguments(
        callee,
        expression.argumentList,
        unit,
        (e) => lowerExpression(context, e),
      );
      return context.current!.emit(DirectCall(target, args));
    case ast.BinaryExpression(
      :final leftOperand,
      :final rightOperand,
      :final operator,
    ):
      final left = lowerExpression(context, leftOperand);
      if (operator.type == .AMPERSAND_AMPERSAND || operator.type == .BAR_BAR) {
        final and = operator.type == .AMPERSAND_AMPERSAND;
        if (left case Constant(value: final bool value)) {
          return value == and ? lowerExpression(context, rightOperand) : left;
        }
        final branch = context.current!, saved = context.saveLocals();
        final rhs = context.addBlock();
        context.current = rhs;
        final right = lowerExpression(context, rightOperand);
        final rhsEnd = context.current!;
        final (skip, evaluated) = context.join(saved, (.boolean, left, right));
        final enter = Jump(rhs);
        branch.finish(Branch(left, and ? enter : skip, and ? skip : enter));
        rhsEnd.finish(evaluated);
        return skip.target.parameters.first;
      }
      return _integerOperation(
        context,
        expression,
        operator,
        left,
        rightOperand,
      );
    default:
      unsupported(
        unit,
        expression,
        'expression starting with ${expression.beginToken.lexeme}',
      );
  }
}

Constant _integerLiteral(
  FunctionContext context,
  ast.Expression site,
  ast.IntegerLiteral literal, {
  required bool negated,
}) {
  if (site.staticType!.isDartCoreDouble) {
    if (literal.parseDoubleValue(negated: negated) case final d?) {
      return .floating(d);
    }
  } else if (literal.parseIntValue(negated: negated) case final i?) {
    return .integer(i);
  }
  unsupported(context.unit, site, 'numeric literal');
}

Value _updateLocal(
  FunctionContext context,
  ast.CompoundAssignmentExpression expression,
) {
  final (operator, rhs) = switch (expression) {
    ast.AssignmentExpression(:final operator, :final rightHandSide) => (
      operator,
      rightHandSide,
    ),
    ast.PrefixExpression(:final operator) ||
    ast.PostfixExpression(:final operator)
        when operator.type == .PLUS_PLUS || operator.type == .MINUS_MINUS =>
      (operator, null),
    _ => unsupported(context.unit, expression, 'operator expression'),
  };
  final variable = expression.writeElement;
  final old = context.locals[variable];
  if (variable is! VariableElement ||
      old == null ||
      (operator.type != .EQ && expression.readElement != variable)) {
    unsupported(context.unit, expression, 'non-local assignment');
  }
  // The right operand can write the same local. Its previous value remains
  // the receiver of a compound operator and the result of a postfix update.
  final value = operator.type == .EQ
      ? lowerExpression(context, rhs!)
      : _integerOperation(context, expression, operator, old, rhs);
  if (!valueType(variable.type, context.unit, expression).accepts(value.type)) {
    unsupported(context.unit, expression, 'implicit conversion');
  }
  context.locals[variable] = value;
  return expression is ast.PostfixExpression ? old : value;
}

Value _integerOperation(
  FunctionContext context,
  ast.Expression site,
  Token operator,
  Value left,
  ast.Expression? rhs,
) {
  final IntOperator op = switch (operator.type) {
    .PLUS || .PLUS_EQ || .PLUS_PLUS => .add,
    .MINUS || .MINUS_EQ || .MINUS_MINUS => .subtract,
    .STAR || .STAR_EQ => .multiply,
    .LT => .lessThan,
    _ => unsupported(context.unit, site, operator.lexeme),
  };
  if (left.type != .integer ||
      (rhs != null &&
          valueType(rhs.staticType!, context.unit, rhs) != .integer)) {
    unsupported(context.unit, site, 'non-integer operator');
  }
  final right = rhs == null
      ? const Constant.integer(1)
      : lowerExpression(context, rhs);
  return context.current!.emit(IntBinary(op, left, right));
}
