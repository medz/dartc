import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';

import 'builder.dart';
import 'scope.dart';
import 'types.dart';

/// Ways to leave a `try` that its `finally` block comes before.
final class _Finally(final Join join) {
  /// What to do after the block, given the value that the function returns.
  final exits = <void Function(HirValue value)>[];
}

/// What a `finally` block comes after: a throw, the end of the `try`, or one of
/// the exits, which are numbered from [_firstExit].
const _thrown = 0, _completed = 1, _firstExit = 2;

/// Translates `try` statements.
final class TryTranslator(
  final ProgramScope _scope,
  final FunctionBuilder _builder,
  final void Function(Statement node) _statement,
) {
  final _finallies = <_Finally>[];

  /// The number of `finally` blocks around the current statement.
  int get depth => _finallies.length;

  /// Does [exit], which goes to where only [depth] `finally` blocks are around,
  /// after running the others. [value] is kept for it.
  void leave(
    int depth,
    void Function(HirValue? value) exit, [
    HirValue? value,
  ]) {
    if (_finallies.length <= depth) return exit(value);
    final innermost = _finallies.last;
    final number = _firstExit + innermost.exits.length;
    innermost.exits.add((kept) {
      leave(depth, exit, value == null ? null : kept);
    });
    _enterFinally(innermost, number, value: value);
  }

  void translate(TryStatement node) {
    final finallyBlock = node.finallyBlock;
    if (finallyBlock == null) return _tryCatch(node);
    // Made before the body declares variables of its own.
    final after = _builder.join(node);
    final result = _builder.function.result;
    final scope = _Finally(
      _builder.joinAll(node, [
        .integer,
        .reference,
        .reference,
        result ?? .integer,
      ]),
    );
    final caught = _builder.joinAll(node, const [.reference, .reference]);
    _finallies.add(scope);
    _builder.within(caught, () {
      node.catchClauses.isEmpty ? _statement(node.body) : _tryCatch(node);
    });
    _enterFinally(scope, _completed);
    _builder.enter(caught);
    final [exception, trace] = _builder.resultsOf(caught);
    _enterFinally(scope, _thrown, exception: exception, trace: trace);
    _finallies.removeLast();
    _builder.enter(scope.join);
    _statement(finallyBlock);
    _leaveFinally(scope, after);
  }

  void _enterFinally(
    _Finally scope,
    int reason, {
    HirValue? exception,
    HirValue? trace,
    HirValue? value,
  }) => _builder.jumpWith(scope.join, [
    _builder.add(HirConst(reason)),
    exception ?? _builder.add(HirNull()),
    trace ?? _builder.add(HirNull()),
    value ?? _builder.placeholder(_builder.function.result ?? .integer),
  ]);

  /// Continues as the `try` would have without its `finally` block.
  void _leaveFinally(_Finally scope, Join after) {
    final [reason, exception, trace, value] = _builder.resultsOf(scope.join);
    final cases = [
      (_thrown, () => _builder.raise(exception, trace)),
      for (final (i, exit) in scope.exits.indexed)
        (_firstExit + i, () => exit(value)),
    ];
    void test(int index) {
      if (index == cases.length) return _builder.jump(after);
      final (number, work) = cases[index];
      final same = _builder.add(
        HirCompare(.equal, reason, _builder.add(HirConst(number))),
      );
      _builder.branch(same, work, () => test(index + 1));
    }

    test(0);
    _builder.enter(after);
  }

  void _tryCatch(TryStatement node) {
    final after = _builder.join(node);
    final caught = _builder.joinAll(node.body, const [.reference, .reference]);
    _builder.within(caught, () => _statement(node.body));
    _builder
      ..jump(after)
      ..enter(caught);
    final [exception, trace] = _builder.resultsOf(caught);
    void clause(int index) {
      if (index == node.catchClauses.length) {
        return _builder.raise(exception, trace);
      }
      final clause_ = node.catchClauses[index];
      void body() {
        _catch(clause_, exception, trace);
        _builder.jump(after);
      }

      final test = _test(clause_);
      if (test == null) return body();
      _builder.branch(
        _builder.add(HirIsInstance(test, exception)),
        body,
        () => clause(index + 1),
      );
    }

    clause(0);
    _builder.enter(after);
  }

  /// What [clause] tests, or null if it catches everything.
  HirTypeTest? _test(CatchClause clause) {
    final annotation = clause.exceptionType, type = annotation?.type;
    if (annotation == null || type is DynamicType) return null;
    final class_ =
        classOf(type) ??
        (throw _builder.unit.unsupported(annotation, 'catching $type'));
    return class_.isDartCoreObject ? null : _scope.testOf(class_);
  }

  void _catch(CatchClause clause, HirValue exception, HirValue trace) {
    for (final (parameter, value) in [
      (clause.exceptionParameter, exception),
      (clause.stackTraceParameter, trace),
    ]) {
      final variable = parameter?.declaredFragment?.element;
      if (variable == null) continue;
      _builder
        ..declare(variable, .reference)
        ..assign(variable, value);
    }
    _builder.caught.add((exception, trace));
    _statement(clause.body);
    _builder.caught.removeLast();
  }
}
