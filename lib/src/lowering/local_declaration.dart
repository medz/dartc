import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:dartc/ir.dart';

import 'function_context.dart';

/// Declares locals with the same initialization rules in statements and loops.
void lowerVariables(
  FunctionContext context,
  ast.VariableDeclarationList declarations,
  Value? Function(ast.Expression) evaluate,
) {
  for (final variable in declarations.variables) {
    final initializer = variable.initializer;
    final local = variable.declaredFragment!.element;
    final type = context.typeOf(local.type, variable);
    if (variable.isLate) {
      context.declareLate(variable, type);
      continue;
    }
    if (initializer == null && (local.isFinal || !type.accepts(.nullType))) {
      context.declareUninitialized(local, type);
      continue;
    }
    final value = switch (initializer) {
      null => const Constant.nullValue(),
      _ when local.isConst => context.bindings.constantOf(
        local,
        context.unit,
        initializer,
      ),
      _ => evaluate(initializer),
    };
    if (value == null) return;
    context.declare(local, type, value);
    if (context.current == null) return;
  }
}
