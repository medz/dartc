import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';

import 'assigned.dart';
import 'assertions.dart';
import 'builder.dart';
import 'coroutine_body.dart';
import 'describe.dart';
import 'expression.dart';
import 'scope.dart';
import 'try_statement.dart';

/// Translates the statements of one function.
final class StatementTranslator(
  final ProgramScope _scope,
  final FunctionBuilder _builder,
) {
  final expressions = ExpressionTranslator(_scope, _builder);
  late final assertions = AssertionTranslator(_scope, _builder, expressions);
  late final _tries = TryTranslator(_scope, _builder, statement);
  late final _coroutine = CoroutineBody(_scope, _builder, expressions);

  /// Where `break` and `continue` statements go, by the statement they name,
  /// with the number of `finally` blocks around.
  final _breaks = <AstNode, (Join, int)>{};
  final _continues = <AstNode, (Join, int)>{};

  Never _unsupported(AstNode node, String what) =>
      throw _builder.unit.unsupported(node, what);

  void body(FunctionBody body) {
    _body(body);
    _builder.stay();
    if (_builder.coroutine != null) _end();
  }

  /// Ends a function that can be left in the middle.
  void _end() => _leave(_builder.add(HirNull()));

  void _leave(HirValue value) => _tries.leave(0, (kept) {
    _builder.stay();
    _coroutine.finish(kept!);
  }, value);

  void _body(FunctionBody body) {
    switch (body) {
      case BlockFunctionBody(:final block):
        statement(block);
      case ExpressionFunctionBody(:final expression):
        _return(expression);
      default:
        _unsupported(body, 'a function without a body');
    }
  }

  void statement(Statement node) {
    final scope = _builder.scope;
    _statement(node);
    if (node is VariableDeclarationStatement ||
        node is PatternVariableDeclarationStatement) {
      return;
    }
    _builder.leave(scope);
  }

  void _statement(Statement node) {
    switch (node) {
      case Block(:final statements):
        statements.forEach(statement);
      case EmptyStatement():
        break;
      case AssertStatement():
        assertions.check(node);
      case ExpressionStatement(:final expression):
        expressions.effect(expression);
      case VariableDeclarationStatement(:final variables):
        expressions.loops.declare(variables);
      case IfStatement(:final expression, :final caseClause):
        final scope = _builder.scope;
        expressions.patterns.choose(
          node,
          (expression, caseClause),
          () {
            statement(node.thenStatement);
            _builder.stay(scope);
          },
          () {
            if (node.elseStatement case final other?) statement(other);
          },
        );
      case PatternVariableDeclarationStatement(:final declaration):
        expressions.loops.destructure(declaration);
      case WhileStatement():
        _while(node);
      case DoStatement():
        _do(node);
      case YieldStatement():
        _coroutine.yieldStatement(node, _end);
      case ForStatement(awaitKeyword: _?, :final ForEachParts forLoopParts):
        expressions.loops.eachOfStream(
          node,
          forLoopParts,
          () => statement(node.body),
          within: (exit, next) {
            _breaks[node] = (exit, _tries.depth);
            _continues[node] = (next, _tries.depth);
          },
          protect: (body, last) => _tries.protect(node, body, last),
        );
      case ForStatement(:final forLoopParts):
        expressions.loops.translate(
          node,
          forLoopParts,
          () => statement(node.body),
          within: (exit, next) {
            _breaks[node] = (exit, _tries.depth);
            _continues[node] = (next, _tries.depth);
          },
        );
      case SwitchStatement():
        _switch(node);
      case LabeledStatement(statement: final inner):
        final exit = _builder.join(node);
        _breaks[inner] = (exit, _tries.depth);
        statement(inner);
        _builder
          ..jump(exit)
          ..enter(exit);
      case BreakStatement(:final target):
        _goTo(_breaks[target] ?? _unsupported(node, 'this break'));
      case ContinueStatement(:final target):
        _goTo(_continues[target] ?? _unsupported(node, 'this continue'));
      case FunctionDeclarationStatement(:final functionDeclaration):
        expressions.closures.declare(functionDeclaration);
      case TryStatement():
        _tries.translate(node);
      case ReturnStatement(:final expression):
        _return(expression);
      default:
        _unsupported(node, describe(node));
    }
  }

  void _goTo((Join, int) target) {
    final (join, depth) = target;
    _tries.leave(depth, (_) {
      _builder.stay();
      _builder.jump(join);
    });
  }

  void _return(Expression? expression) {
    if (_builder.coroutine != null) {
      final value = expression == null
          ? _builder.add(HirNull())
          : expressions.valueAsObject(expression, _builder.returnType!);
      return _leave(value);
    }
    final result = _builder.function.result;
    if (result == null) {
      if (expression != null) expressions.effect(expression);
      // Objects stay through what `finally` does, too.
      _tries.leave(0, (_) {
        _builder.stay();
        _builder.end(HirReturn());
      });
    } else {
      final value = expression == null
          ? _builder.fallback?.call() ?? _builder.add(HirNull())
          : expressions.valueTo(expression, _builder.returnType!);
      _tries.leave(0, (kept) {
        _builder.stay();
        _builder.end(HirReturn(kept));
      }, value);
    }
  }

  /// Runs [ifTrue] or leaves for [exit], depending on [condition].
  void _whileTrue(Expression? condition, Join exit, void Function() ifTrue) {
    if (condition == null) {
      ifTrue();
    } else {
      _builder.branch(
        expressions.condition(condition),
        ifTrue,
        () => _builder.jump(exit),
      );
    }
    _builder.enter(exit);
  }

  void _while(WhileStatement node) {
    final head = _builder.join(node), exit = _builder.join(node);
    _breaks[node] = (exit, _tries.depth);
    _continues[node] = (head, _tries.depth);
    _builder
      ..jump(head)
      ..enter(head);
    _whileTrue(node.condition, exit, () {
      statement(node.body);
      _builder.jump(head);
    });
  }

  void _do(DoStatement node) {
    final head = _builder.join(node), exit = _builder.join(node);
    final test = _builder.join(node);
    _breaks[node] = (exit, _tries.depth);
    _continues[node] = (test, _tries.depth);
    _builder
      ..jump(head)
      ..enter(head);
    statement(node.body);
    _builder
      ..jump(test)
      ..enter(test);
    _whileTrue(node.condition, exit, () => _builder.jump(head));
  }

  void _switch(SwitchStatement node) {
    final value = expressions.value(node.expression);
    final type = node.expression.staticType!;
    final exit = _builder.join(node), scope = _builder.scope;
    _breaks[node] = (exit, _tries.depth);
    final groups = _groups(node.members);
    final patterns = [
      for (final group in groups)
        for (final member in group)
          if (member is SwitchPatternCase) member.guardedPattern.pattern,
    ];
    expressions.patterns.matching(patterns, () {
      final bodies = [for (final group in groups) _bodyOf(node, group)];
      for (final (i, group) in groups.indexed) {
        _group(node, group, (value, type), bodies[i], exit, scope);
      }
    });
    _builder
      ..jump(exit)
      ..enter(exit);
  }

  /// The cases of [members] that share statements.
  static List<List<SwitchMember>> _groups(List<SwitchMember> members) {
    final groups = <List<SwitchMember>>[];
    var isOpen = false;
    for (final member in members) {
      if (isOpen) {
        groups.last.add(member);
      } else {
        groups.add([member]);
      }
      isOpen = member.statements.isEmpty;
    }
    return groups;
  }

  /// Where the statements of [group] start.
  Join _bodyOf(SwitchStatement node, List<SwitchMember> group) {
    final patterns = [
      for (final member in group)
        if (member is SwitchPatternCase) member.guardedPattern.pattern,
    ];
    expressions.patterns.declareIn(patterns);
    final body = _builder.joinAll(node, const [], [
      ...patterns.expand(declaredIn),
    ]);
    for (final member in group) {
      _continues[member] = (body, _tries.depth);
    }
    return body;
  }

  /// Goes to [body] if one of [group] matches, or goes on. What is declared
  /// after [scope] ends with the body.
  void _group(
    SwitchStatement node,
    List<SwitchMember> group,
    (HirValue, DartType) value,
    Join body,
    Join exit,
    int scope,
  ) {
    final patterns = expressions.patterns;
    for (final member in group) {
      switch (member) {
        case SwitchPatternCase(:final guardedPattern):
          final next = patterns.join(node);
          patterns.match(guardedPattern, value.$1, value.$2, next);
          _builder
            ..jump(body)
            ..enter(next);
        // Before language version 3.0, there were no patterns.
        case SwitchCase(:final expression):
          final next = patterns.join(node);
          patterns.matchConstant(member, expression, value, next);
          _builder
            ..jump(body)
            ..enter(next);
        case SwitchDefault():
          _builder.jump(body);
      }
    }
    final after = patterns.join(node);
    _builder
      ..jump(after)
      ..enter(body);
    group.last.statements.forEach(statement);
    _builder.leave(scope);
    _builder
      ..jump(exit)
      ..enter(after);
  }
}
