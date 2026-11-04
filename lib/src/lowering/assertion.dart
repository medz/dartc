import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:dartc/ir.dart';

import 'expression.dart';
import 'function_context.dart';

/// Evaluates enabled assertions, including their message only on failure.
void lowerAssert(
  FunctionContext context,
  ast.Expression condition,
  ast.Expression? message,
) {
  if (!context.bindings.enableAssertions) return;
  final test = lowerExpression(context, condition);
  if (test == null) return;
  context.branch(test, () => null, () {
    final value = message == null ? null : lowerExpression(context, message);
    if (context.current != null) {
      context.normal(context.emit(AssertionFailure(value)));
    }
    return null;
  });
}
