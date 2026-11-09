import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:dartc/ir.dart';

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
      final type = context.typeOf(filter.type!, filter);
      context.guard(context.testType(exception, type), next);
    }
    if (context.current != null) {
      final enclosing = context.caught;
      context.caught = (exception, trace);
      context.inScope(() {
        if (clause.exceptionParameter?.declaredFragment?.element
            case final e?) {
          final type = context.typeOf(e.type, clause);
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

/// Routes transfers that leave a try statement through its `finally` block.
final class FinallyRegion(
  final FunctionContext _context,
  final ast.AstNode _statement,
  ValueType resultType,
) {
  final JumpTarget _normal = .new(_context);
  final JumpTarget _throw = .new(_context, [.object, .stackTrace]);
  final JumpTarget _return = .new(_context, [resultType]);
  final _jumps = <(ast.AstNode, void Function()), JumpTarget>{};

  /// Saves the result before the finalizer can change its source variables.
  void returnValue(Value? result) =>
      _return.jump([result ?? const Constant.nullValue()]);

  /// Returns true when reaching [target] requires running this finalizer.
  bool interceptJump(ast.AstNode target, void Function() jump) {
    for (var parent = target.parent; parent != null; parent = parent.parent) {
      if (parent == _statement) return false;
    }
    (_jumps[(target, jump)] ??= _normal.sibling(const [])).jump();
    return true;
  }

  /// Runs cleanup for each reachable destination, sharing sites with the same exit.
  void lower(
    void Function() protected,
    void Function() cleanup,
    void Function(Value) resumeReturn,
    void Function(ast.AstNode, void Function()) resumeJump,
  ) {
    final outer = _context.handler;
    _context.handler = _throw;
    protected();
    _context.handler = outer;
    if (!_throw.hasIncoming && !_return.hasIncoming && _jumps.isEmpty) {
      if (_context.current != null) cleanup();
      return;
    }
    _normal.jump();
    if (_throw.enter() case final entry?) {
      cleanup();
      if (_context.current != null) {
        _context.raise(entry.parameters[0], entry.parameters[1]);
      }
    }
    if (_return.enter() case final entry?) {
      cleanup();
      if (_context.current != null) resumeReturn(entry.parameters.first);
    }
    for (final MapEntry(key: (target, jump), value: entry) in _jumps.entries) {
      entry.enter();
      cleanup();
      if (_context.current != null) resumeJump(target, jump);
    }
    if (_normal.enter() != null) cleanup();
  }
}
