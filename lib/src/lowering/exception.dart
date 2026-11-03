import 'package:analyzer/dart/ast/ast.dart' as ast;

import 'bindings.dart';
import 'function_context.dart';

/// Checks catch clauses in source order and preserves the original throw on a miss.
void lowerTryCatch(
  FunctionContext context,
  ast.TryStatement statement,
  void Function(ast.Block) lower,
) {
  final handler = JumpTarget(context, [.object, .stackTrace]);
  final done = JumpTarget(context);
  final outer = context.handler;
  context.handler = handler;
  lower(statement.body);
  context.handler = outer;
  if (!handler.hasIncoming) return;
  done.jump();
  final entry = handler.enter()!;
  final exception = entry.parameters[0], trace = entry.parameters[1];
  for (final clause in statement.catchClauses) {
    final next = JumpTarget(context);
    final filter = clause.exceptionType;
    if (filter != null) {
      final type = valueType(filter.type!, context.unit, filter);
      context.guard(context.testType(exception, type), next);
    }
    if (context.current != null) {
      final enclosing = context.caught;
      context.caught = (exception, trace);
      context.inScope(() {
        if (clause.exceptionParameter?.declaredFragment?.element
            case final e?) {
          final type = valueType(e.type, context.unit, clause);
          context.declare(e, type, context.cast(exception, type));
        }
        if (clause.stackTraceParameter?.declaredFragment?.element
            case final s?) {
          context.declare(s, .stackTrace, trace);
        }
        lower(clause.body);
      });
      context.caught = enclosing;
      done.jump();
    }
    if (next.enter() == null) break;
  }
  if (context.current != null) context.raise(exception, trace);
  done.enter();
}
