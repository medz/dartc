import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/ir.dart';

import 'bindings.dart';
import 'exception.dart';
import 'expression.dart';
import 'function_context.dart';
import 'pattern.dart';
import 'switch_statement.dart';

/// Builds the blocks and local bindings for a resolved synchronous function.
final class FunctionLowering(
  ResolvedUnitResult unit,
  Bindings bindings,
  final ExecutableElement element,
  final ast.AstNode site,
  final ast.FunctionBody? body,
) {
  final FunctionContext context = .new(
    unit,
    bindings,
    element is ConstructorElement || body == null
        ? (variable) => !variable.isFinal
        : body.isPotentiallyMutatedInScope,
  );
  final _breaks = <ast.AstNode, JumpTarget>{};
  final _continues = <ast.AstNode, void Function()>{};
  FinallyRegion? _finally;
  late final _target = context.bindings.target(element, context.unit, site);

  /// Lowers the body and verifies the resulting function before returning it.
  IrFunction run([void Function(FunctionContext)? initialize]) {
    final body = this.body;
    if (body != null && (body.isAsynchronous || body.isGenerator)) {
      unsupported(context.unit, site, 'async or generator bodies');
    }
    context.current = context.addBlock(_target.parameterTypes);
    final hasReceiver = _target.kind.hasReceiver;
    if (hasReceiver) context.receiver = context.current!.parameters.first;
    for (final (i, parameter) in element.formalParameters.indexed) {
      final input = context.current!.parameters[i + (hasReceiver ? 1 : 0)];
      context.declare(parameter, input.type, input);
    }
    initialize?.call(context);
    if (context.current != null) {
      switch (body) {
        case null || ast.EmptyFunctionBody() when _target.kind == .initializer:
          _return(null);
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
          unsupported(context.unit, site, 'function body');
      }
    }
    return .new(
      _target,
      context.blocks,
      defaults: context.bindings.defaults(element),
    );
  }

  void _return(Value? value) {
    if (context.current == null) return;
    if (_finally case final region?) {
      region.returnValue(value);
      return;
    }
    context.current!.finish(Return(value));
    context.current = null;
  }

  void _jump(ast.AstNode target, void Function() jump) {
    if (_finally?.interceptJump(target, jump) != true) jump();
  }

  void _try(ast.TryStatement statement) {
    void body() {
      if (statement.catchClauses.isEmpty) {
        _scoped(statement.body);
      } else {
        lowerTryCatch(context, statement, _scoped);
      }
    }

    final finalizer = statement.finallyBlock;
    if (finalizer == null || finalizer.statements.isEmpty) {
      body();
      return;
    }
    final enclosing = _finally;
    final region = FinallyRegion(context, statement, _target.returnType);
    region.lower(
      () {
        _finally = region;
        body();
        _finally = enclosing;
      },
      () => _scoped(finalizer),
      _return,
      _jump,
    );
  }

  void _scoped(ast.Statement? statement) {
    if (statement == null) return;
    context.inScope(() {
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
      final local = variable.declaredFragment!.element;
      final type = context.typeOf(local.type, variable);
      if (variable.isLate ||
          (initializer == null && !type.accepts(.nullType))) {
        unsupported(
          context.unit,
          variable,
          'late or uninitialized non-nullable local',
        );
      }
      final value = switch (initializer) {
        null => const Constant.nullValue(),
        _ when local.isConst => context.bindings.constantOf(
          local,
          context.unit,
          initializer,
        ),
        _ => lowerExpression(context, initializer),
      };
      if (value == null) return;
      if (!type.accepts(value.type)) {
        unsupported(
          context.unit,
          initializer ?? variable,
          'implicit conversion',
        );
      }
      context.declare(local, type, value);
    }
  }

  void _patternDeclaration(ast.PatternVariableDeclaration declaration) {
    declarePattern(
      context,
      declaration.pattern,
      lowerExpression(context, declaration.expression),
    );
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
      case ast.PatternVariableDeclarationStatement(:final declaration):
        _patternDeclaration(declaration);
      case ast.ExpressionStatement(:final expression):
        lowerExpression(context, expression);
      case ast.TryStatement():
        _try(statement);
      case ast.IfStatement(caseClause: ast.CaseClause(:final guardedPattern)):
        final subject = lowerExpression(context, statement.expression);
        if (subject == null) return;
        final failed = JumpTarget(context), done = JumpTarget(context);
        context.inScope(() {
          matchGuarded(
            context,
            guardedPattern,
            subject,
            failed,
            (e) => lowerExpression(context, e),
          );
          if (context.current != null) _scoped(statement.thenStatement);
        });
        if (failed.hasIncoming) {
          done.jump();
          failed.enter();
          _scoped(statement.elseStatement);
          done.enter();
        }
      case ast.IfStatement(caseClause: null):
        final condition = lowerExpression(context, statement.expression);
        if (condition == null) return;
        context.branch(
          condition,
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
      case ast.WhileStatement() ||
          ast.DoStatement() ||
          ast.ForStatement() ||
          ast.SwitchStatement():
        _breakable(statement);
      case ast.BreakStatement(:final target) ||
          ast.ContinueStatement(:final target):
        final jump = statement is ast.BreakStatement
            ? _breaks[target]?.jump
            : _continues[target];
        if (jump == null) {
          unsupported(context.unit, statement, 'jump target');
        }
        _jump(target!, jump);
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
      case ast.SwitchStatement():
        lowerSwitchStatement(context, statement, exit, _continues, _statement);
      case ast.WhileStatement(:final body, :final condition):
        _loop(statement, body, condition, exit);
      case ast.DoStatement(:final body, :final condition):
        _loop(statement, body, condition, exit, testAfterBody: true);
      case ast.ForStatement(
        :final body,
        forLoopParts: final ast.ForParts parts,
      ):
        context.inScope(() {
          switch (parts) {
            case ast.ForPartsWithDeclarations(:final variables):
              _variables(variables);
            case ast.ForPartsWithExpression(:final initialization):
              if (initialization != null) {
                lowerExpression(context, initialization);
              }
            case ast.ForPartsWithPattern(:final variables):
              _patternDeclaration(variables);
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
    if (context.current == null) return;
    final header = JumpTarget(context)
      ..jump()
      ..enter();
    final next = testAfterBody || updates.isNotEmpty
        ? JumpTarget(context)
        : header;
    _continues[statement] = next.jump;
    if (!testAfterBody && condition != null) {
      context.guard(lowerExpression(context, condition), exit);
    }
    if (context.current != null) {
      _scoped(body);
      if (next != header) next.enter();
      if (context.current != null) {
        for (final update in updates) {
          if (lowerExpression(context, update) == null) break;
        }
        if (testAfterBody) {
          context.guard(lowerExpression(context, condition!), exit);
        }
        header.jump();
      }
    }
    _continues.remove(statement);
  }
}
