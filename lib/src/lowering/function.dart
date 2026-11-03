import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/ir.dart';

import 'bindings.dart';
import 'expression.dart';
import 'function_context.dart';

/// Builds the blocks and local bindings for a resolved synchronous function.
final class FunctionLowering(
  ResolvedUnitResult unit,
  TargetBindings bindings,
  final TopLevelFunctionElement element,
  final ast.FunctionBody body,
) {
  final FunctionContext context = .new(unit, bindings);
  final _locals = <VariableElement>[];
  final _breaks = <ast.AstNode, JumpTarget>{};
  final _continues = <ast.AstNode, JumpTarget>{};
  late final _target = context.bindings.target(element, context.unit, body);

  /// Lowers the body and verifies the resulting function before returning it.
  IrFunction run() {
    if (body.isAsynchronous || body.isGenerator) {
      unsupported(context.unit, body, 'async or generator bodies');
    }
    context.current = context.addBlock(_target.parameterTypes);
    for (final (i, parameter) in element.formalParameters.indexed) {
      final input = context.current!.parameters[i];
      _declare(parameter, input.type, input);
    }
    switch (body) {
      case ast.ExpressionFunctionBody(:final expression):
        _return(lowerExpression(context, expression));
      case ast.BlockFunctionBody(:final block):
        _statement(block);
        if (context.current != null) {
          if (!_target.returnType.accepts(.nullType)) {
            unsupported(context.unit, body, 'implicit return');
          }
          _return(null);
        }
      default:
        unsupported(context.unit, body, 'function body');
    }
    return .new(_target, context.blocks);
  }

  void _return(Value? value) {
    context.current!.finish(Return(value));
    context.current = null;
  }

  void _declare(VariableElement variable, ValueType type, Value initial) {
    context.locals[variable] = initial;
    _locals.add(variable);
    if (body.isPotentiallyMutatedInScope(variable)) {
      context.mutableLocals.add((variable, type));
    }
  }

  void _inScope(void Function() lower) {
    final mark = _locals.length;
    final mutableMark = context.mutableLocals.length;
    lower();
    while (_locals.length > mark) {
      context.locals.remove(_locals.removeLast());
    }
    context.mutableLocals.length = mutableMark;
  }

  void _scoped(ast.Statement? statement) {
    if (statement == null) return;
    _inScope(() {
      if (statement is ast.Block) {
        for (final child in statement.statements) {
          if (context.current == null) break;
          _statement(child);
        }
      } else {
        _statement(statement);
      }
    });
  }

  void _variables(ast.VariableDeclarationList declarations) {
    for (final variable in declarations.variables) {
      final initializer = variable.initializer;
      if (variable.isLate || initializer == null) {
        unsupported(context.unit, variable, 'late or uninitialized locals');
      }
      final local = variable.declaredFragment!.element;
      final type = valueType(local.type, context.unit, variable);
      final value = local.isConst
          ? scalarConstant(local, context.unit, initializer)
          : lowerExpression(context, initializer);
      if (!type.accepts(value.type)) {
        unsupported(context.unit, initializer, 'implicit conversion');
      }
      _declare(local, type, value);
    }
  }

  void _statement(ast.Statement statement) {
    switch (statement) {
      case ast.Block():
        _scoped(statement);
      case ast.EmptyStatement():
        return;
      case ast.ReturnStatement(:final expression):
        _return(
          expression == null ? null : lowerExpression(context, expression),
        );
      case ast.VariableDeclarationStatement(:final variables):
        _variables(variables);
      case ast.ExpressionStatement(:final expression):
        lowerExpression(context, expression);
      case ast.IfStatement(caseClause: null):
        context.branch(
          lowerExpression(context, statement.expression),
          () {
            _scoped(statement.thenStatement);
            return null;
          },
          () {
            _scoped(statement.elseStatement);
            return null;
          },
        );
      case ast.LabeledStatement(:final statement):
        _breakable(statement);
      case ast.WhileStatement() || ast.DoStatement() || ast.ForStatement():
        _breakable(statement);
      case ast.BreakStatement(:final target) ||
          ast.ContinueStatement(:final target):
        final destination = statement is ast.BreakStatement
            ? _breaks[target]
            : _continues[target];
        if (destination == null) {
          unsupported(context.unit, statement, 'jump target');
        }
        destination.jump();
      default:
        unsupported(
          context.unit,
          statement,
          'statement starting with ${statement.beginToken.lexeme}',
        );
    }
  }

  void _breakable(ast.Statement statement) {
    final exit = _breaks[statement] = JumpTarget(context);
    switch (statement) {
      case ast.WhileStatement(:final body, :final condition):
        _loop(statement, body, condition, exit);
      case ast.DoStatement(:final body, :final condition):
        _loop(statement, body, condition, exit, testAfterBody: true);
      case ast.ForStatement(
        :final body,
        forLoopParts: final ast.ForParts parts,
      ):
        _inScope(() {
          switch (parts) {
            case ast.ForPartsWithDeclarations(:final variables):
              _variables(variables);
            case ast.ForPartsWithExpression(:final initialization):
              if (initialization != null) {
                lowerExpression(context, initialization);
              }
            case ast.ForPartsWithPattern():
              unsupported(context.unit, parts, 'for pattern initializer');
          }
          _loop(
            statement,
            body,
            parts.condition,
            exit,
            updates: parts.updaters,
          );
        });
      case ast.ForStatement():
        unsupported(context.unit, statement, 'for-in');
      default:
        _statement(statement);
    }
    _breaks.remove(statement);
    exit.enter();
  }

  void _loop(
    ast.Statement statement,
    ast.Statement body,
    ast.Expression? condition,
    JumpTarget exit, {
    bool testAfterBody = false,
    Iterable<ast.Expression> updates = const [],
  }) {
    final header = JumpTarget(context)
      ..jump()
      ..enter();
    final next = _continues[statement] = testAfterBody || updates.isNotEmpty
        ? JumpTarget(context)
        : header;
    if (!testAfterBody && condition != null) _guard(condition, exit);
    if (context.current != null) {
      _scoped(body);
      if (next != header) next.enter();
      if (context.current != null) {
        for (final update in updates) {
          lowerExpression(context, update);
        }
        if (testAfterBody) _guard(condition!, exit);
        header.jump();
      }
    }
    _continues.remove(statement);
  }

  void _guard(ast.Expression expression, JumpTarget exit) {
    final condition = lowerExpression(context, expression);
    if (condition case Constant(value: final bool passes)) {
      if (!passes) exit.jump();
    } else {
      final body = context.addBlock();
      context.current!.finish(Branch(condition, .new(body), exit.edge()));
      context.current = body;
    }
  }
}
