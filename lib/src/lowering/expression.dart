import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/ast/token.dart' show Token;
import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/ir.dart';

import 'bindings.dart';
import 'function_context.dart';
import 'operators.dart';
import 'pattern.dart';

/// Returns the emitted operand, or `null` when [expression] cannot complete normally.
Value? lowerExpression(FunctionContext context, ast.Expression expression) =>
    context.normal(_lower(context, expression));

Value? _lower(FunctionContext context, ast.Expression expression) {
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
    case ast.IsExpression(:final expression, :final type, :final notOperator):
      final input = lowerExpression(context, expression);
      return input == null
          ? null
          : context.testType(
              input,
              valueType(type.type!, unit, type),
              negated: notOperator != null,
            );
    case ast.AsExpression(:final expression, :final type):
      final input = lowerExpression(context, expression);
      return input == null
          ? null
          : context.cast(input, valueType(type.type!, unit, type));
    case ast.PostfixExpression(operator: Token(type: .BANG), :final operand):
      final value = lowerExpression(context, operand);
      return value == null ? null : context.checkNotNull(value);
    case ast.ThrowExpression(:final expression):
      final exception = lowerExpression(context, expression);
      if (exception != null) {
        context.current!.finish(Throw(exception));
        context.current = null;
      }
      return null;
    case ast.ConditionalExpression(
      :final condition,
      :final thenExpression,
      :final elseExpression,
    ):
      final test = lowerExpression(context, condition);
      if (test == null) return null;
      return context.branch(
        test,
        () => lowerExpression(context, thenExpression),
        () => lowerExpression(context, elseExpression),
        valueType(expression.staticType!, unit, expression),
      );
    case ast.SwitchExpression():
      final subject = lowerExpression(context, expression.expression);
      if (subject == null) return null;
      final done = JumpTarget(context, [
        valueType(expression.staticType!, unit, expression),
      ]);
      for (final arm in expression.cases) {
        final next = JumpTarget(context);
        context.inScope(() {
          matchGuarded(
            context,
            arm.guardedPattern,
            subject,
            next,
            (e) => lowerExpression(context, e),
          );
          if (context.current == null) return;
          final result = lowerExpression(context, arm.expression);
          if (result != null) done.jump([result]);
        });
        if (next.enter() == null) break;
      }
      context.current?.finish(const ExhaustivenessFailure());
      context.current = null;
      return done.enter()?.parameters.first;
    case ast.SimpleIdentifier(element: final VariableElement variable)
        when context.locals.containsKey(variable):
      return context.cast(
        context.locals[variable]!,
        valueType(expression.staticType!, unit, expression),
      );
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
      return args == null
          ? null
          : context.current!.emit(DirectCall(target, args));
    case ast.BinaryExpression(
      :final leftOperand,
      :final rightOperand,
      :final operator,
    ):
      final left = lowerExpression(context, leftOperand);
      if (left == null) return null;
      if (operator.type == .QUESTION_QUESTION) {
        return _coalesce(context, expression, left, rightOperand);
      }
      if (operator.type == .AMPERSAND_AMPERSAND || operator.type == .BAR_BAR) {
        final and = operator.type == .AMPERSAND_AMPERSAND;
        if (left case Constant(value: final bool value)) {
          return value == and ? lowerExpression(context, rightOperand) : left;
        }
        return context.shortCircuit(
          left,
          evaluateWhen: and,
          skipped: left,
          resultType: .boolean,
          right: () => lowerExpression(context, rightOperand),
        );
      }
      return lowerBinary(
        context,
        expression,
        operator,
        left,
        lowerExpression(context, rightOperand),
      );
    default:
      unsupported(
        unit,
        expression,
        'expression starting with ${expression.beginToken.lexeme}',
      );
  }
}

Value? _coalesce(
  FunctionContext context,
  ast.Expression site,
  Value left,
  ast.Expression rhs,
) {
  final known = context.refined(left);
  if (known.type == .nullType) return lowerExpression(context, rhs);
  if (!known.type.accepts(.nullType)) return known;
  final test = context.current!.emit(TypeTest(known, .nullType));
  return context.shortCircuit(
    test,
    evaluateWhen: true,
    skipped: test.refinement(false) ?? known,
    resultType: valueType(site.staticType!, context.unit, site),
    right: () => lowerExpression(context, rhs),
  );
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

Value? _updateLocal(
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
  final read = operator.type == .EQ
      ? old
      : context.cast(
          old,
          valueType(expression.readType!, context.unit, expression),
        );
  final value = switch (operator.type) {
    .EQ => lowerExpression(context, rhs!),
    .QUESTION_QUESTION_EQ => _coalesce(context, expression, read, rhs!),
    _ => lowerBinary(
      context,
      expression,
      operator,
      read,
      rhs == null ? const Constant.integer(1) : lowerExpression(context, rhs),
    ),
  };
  if (value == null) return null;
  if (!valueType(variable.type, context.unit, expression).accepts(value.type)) {
    unsupported(context.unit, expression, 'implicit conversion');
  }
  context.locals[variable] = value;
  return expression is ast.PostfixExpression ? read : value;
}
