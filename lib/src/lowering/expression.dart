import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/ir.dart';

import 'bindings.dart';
import 'function_context.dart';

Value lowerExpression(FunctionContext context, ast.Expression expression) {
  final unit = context.unit;
  switch (expression) {
    case ast.BooleanLiteral(:final value):
      return Constant.boolean(value);
    case ast.IntegerLiteral(value: final value?):
      return Constant.integer(value);
    case ast.ParenthesizedExpression(:final expression):
      return lowerExpression(context, expression);
    case ast.SimpleIdentifier(element: final VariableElement variable)
        when context.locals.containsKey(variable):
      return context.locals[variable]!;
    case ast.MethodInvocation(
      methodName: ast.SimpleIdentifier(
        element: final TopLevelFunctionElement callee,
      ),
    ):
      if (expression.target case final receiver?) {
        if (receiver is! ast.SimpleIdentifier ||
            receiver.element is! PrefixElement ||
            (receiver.element as PrefixElement).imports.any(
              (i) => i.prefix?.isDeferred == true,
            )) {
          unsupported(unit, expression, 'call receiver');
        }
      }
      final target = context.bindings.target(callee, unit, expression);
      final values = List<Value?>.filled(target.parameterTypes.length, null);
      for (final argument in expression.argumentList.arguments) {
        final slot = context.bindings.slotOf(argument.correspondingParameter);
        if (slot == null) unsupported(unit, argument, 'argument binding');
        values[slot] = lowerExpression(context, argument.argumentExpression);
      }
      return context.current!.emit(DirectCall(target, values.cast<Value>()));
    case ast.BinaryExpression(
      :final leftOperand,
      :final rightOperand,
      :final operator,
    ):
      final left = lowerExpression(context, leftOperand);
      if (operator.lexeme == '&&' || operator.lexeme == '||') {
        final rhs = context.addBlock(),
            join = context.addBlock([ValueType.boolean]);
        final evaluate = Jump(rhs), skip = Jump(join, [left]);
        final and = operator.lexeme == '&&';
        context.current!.finish(
          Branch(left, and ? evaluate : skip, and ? skip : evaluate),
        );
        context.current = rhs;
        final right = lowerExpression(context, rightOperand);
        context.current!.finish(Jump(join, [right]));
        context.current = join;
        return join.parameters.single;
      }
      final op = switch (operator.lexeme) {
        '+' => IntOperator.add,
        '-' => IntOperator.subtract,
        '*' => IntOperator.multiply,
        '<' => IntOperator.lessThan,
        _ => unsupported(unit, expression, operator.lexeme),
      };
      if (left.type != ValueType.integer ||
          valueType(rightOperand.staticType!, unit, rightOperand) !=
              ValueType.integer) {
        unsupported(unit, expression, 'non-integer operator');
      }
      final right = lowerExpression(context, rightOperand);
      return context.current!.emit(IntBinary(op, left, right));
    default:
      unsupported(
        unit,
        expression,
        'expression starting with ${expression.beginToken.lexeme}',
      );
  }
}
