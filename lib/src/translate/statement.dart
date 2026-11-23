import 'package:analyzer/dart/ast/ast.dart';
import 'package:dartc/hir.dart';

import 'builder.dart';
import 'describe.dart';
import 'expression.dart';
import 'scope.dart';
import 'try_statement.dart';
import 'types.dart';

/// Translates the statements of one function.
final class StatementTranslator(
  final ProgramScope _scope,
  final FunctionBuilder _builder,
) {
  final expressions = ExpressionTranslator(_scope, _builder);
  late final _tries = TryTranslator(_scope, _builder, statement);

  /// Where `break` and `continue` statements go, by the statement they name,
  /// with the number of `finally` blocks around.
  final _breaks = <AstNode, (Join, int)>{};
  final _continues = <AstNode, (Join, int)>{};

  Never _unsupported(AstNode node, String what) =>
      throw _builder.unit.unsupported(node, what);

  void body(FunctionBody body) {
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
    switch (node) {
      case Block(:final statements):
        statements.forEach(statement);
      case EmptyStatement() || AssertStatement():
        // Like the official runtime by default, assertions do nothing.
        break;
      case ExpressionStatement(:final expression):
        expressions.effect(expression);
      case VariableDeclarationStatement(:final variables):
        _declare(variables);
      case IfStatement():
        _if(node);
      case WhileStatement():
        _while(node);
      case DoStatement():
        _do(node);
      case ForStatement(:final forLoopParts):
        if (forLoopParts is! ForParts) _unsupported(node, 'for-in');
        _for(node, forLoopParts);
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
    _tries.leave(depth, (_) => _builder.jump(join));
  }

  void _return(Expression? expression) {
    final result = _builder.function.result;
    if (result == null) {
      if (expression != null) expressions.effect(expression);
      _tries.leave(0, (_) => _builder.end(HirReturn()));
    } else {
      final value = expression == null
          ? _builder.add(HirNull())
          : expressions.valueTo(expression, _builder.returnType!);
      _tries.leave(0, (kept) => _builder.end(HirReturn(kept)), value);
    }
  }

  void _declare(VariableDeclarationList list) {
    for (final declaration in list.variables) {
      final variable = declaration.declaredFragment!.element;
      if (variable.isConst) continue;
      final type =
          valueType(variable.type) ??
          _unsupported(declaration, 'a variable of type ${variable.type}');
      if (list.isLate) {
        expressions.lates.declare(declaration, variable, type);
        continue;
      }
      final initializer = declaration.initializer;
      final value = initializer == null
          ? null
          : expressions.valueTo(initializer, variable.type);
      _builder.declare(variable, type);
      if (value != null) _builder.assign(variable, value);
    }
  }

  void _if(IfStatement node) {
    if (node.caseClause case final clause?) _unsupported(clause, 'if-case');
    final exit = _builder.join(node);
    _builder.branch(
      expressions.condition(node.expression),
      () {
        statement(node.thenStatement);
        _builder.jump(exit);
      },
      () {
        if (node.elseStatement case final other?) statement(other);
        _builder.jump(exit);
      },
    );
    _builder.enter(exit);
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

  void _for(ForStatement node, ForParts parts) {
    switch (parts) {
      case ForPartsWithDeclarations(:final variables):
        if (variables.isLate) _unsupported(variables, 'late loop variables');
        _declare(variables);
      case ForPartsWithExpression(:final initialization):
        if (initialization != null) expressions.effect(initialization);
      default:
        _unsupported(parts, describe(parts));
    }
    final head = _builder.join(node), exit = _builder.join(node);
    final update = _builder.join(node);
    _breaks[node] = (exit, _tries.depth);
    _continues[node] = (update, _tries.depth);
    _builder
      ..jump(head)
      ..enter(head);
    _whileTrue(parts.condition, exit, () {
      statement(node.body);
      _builder
        ..jump(update)
        ..enter(update);
      // Every round has its own variables.
      if (parts case ForPartsWithDeclarations(:final variables)) {
        for (final variable in variables.variables) {
          _builder.renew(variable.declaredFragment!.element);
        }
      }
      parts.updaters.forEach(expressions.effect);
      _builder.jump(head);
    });
  }

  void _switch(SwitchStatement node) {
    final value = expressions.value(node.expression);
    final exit = _builder.join(node);
    _breaks[node] = (exit, _tries.depth);
    _cases(node.members, 0, value, exit);
    _builder.enter(exit);
  }

  /// Tests the cases from [index] on; those without statements share the next.
  void _cases(
    List<SwitchMember> members,
    int index,
    HirValue value,
    Join exit,
  ) {
    if (index == members.length) {
      _builder.jump(exit);
      return;
    }
    final tests = <Expression>[];
    var isDefault = false;
    var last = index;
    while (true) {
      final member = members[last];
      if (member.labels.isNotEmpty) _unsupported(member, 'a labeled case');
      switch (member) {
        case SwitchDefault():
          isDefault = true;
        case SwitchPatternCase(
          guardedPattern: GuardedPattern(
            pattern: ConstantPattern(:final expression),
            whenClause: null,
          ),
        ):
          tests.add(expression);
        default:
          _unsupported(member, 'this kind of case');
      }
      if (member.statements.isNotEmpty || last + 1 == members.length) break;
      last++;
    }
    void body() {
      members[last].statements.forEach(statement);
      _builder.jump(exit);
    }

    if (isDefault) {
      body();
      return;
    }
    _builder.branch(
      _matches(value, tests),
      body,
      () => _cases(members, last + 1, value, exit),
    );
  }

  /// Whether [value] equals any of the constants [tests].
  HirValue _matches(HirValue value, List<Expression> tests) {
    HirValue? result;
    for (final test in tests) {
      final constant = expressions.value(test);
      // Equality of objects may be anything.
      if (constant.type != value.type || constant is HirStatic) {
        _unsupported(test, 'this kind of case');
      }
      final same = _builder.add(HirCompare(.equal, constant, value));
      result = result == null
          ? same
          : _builder.add(HirBoolBinary(.or, result, same));
    }
    return result!;
  }
}
