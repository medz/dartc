import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/ir.dart';

import 'assertion.dart';
import 'bindings.dart';
import 'closures.dart';
import 'exception.dart';
import 'expression.dart';
import 'function_context.dart';
import 'iteration.dart';
import 'local_declaration.dart';
import 'pattern.dart';
import 'switch_statement.dart';

/// Builds the blocks and local bindings for a resolved synchronous function.
final class FunctionLowering._(
  ResolvedUnitResult unit,
  Bindings bindings,
  final ExecutableElement? element,
  final ast.AstNode site,
  final ast.FunctionBody? body,
  final FunctionTarget _target,
  ClosurePlan plan, {
  final int sourceParameterOffset = 0,
}) {
  final FunctionContext context = .new(
    unit,
    bindings,
    element is ConstructorElement || body == null
        ? (variable) => !variable.isFinal
        : body.isPotentiallyMutatedInScope,
    plan,
  );
  final _breaks = <ast.AstNode, JumpTarget>{};
  final _continues = <ast.AstNode, void Function()>{};
  FinallyRegion? _finally;

  /// Appends the outer graph and the lexical bodies it declares to [output].
  static void append(
    List<IrFunction> output,
    ResolvedUnitResult unit,
    Bindings bindings,
    ExecutableElement element,
    ast.AstNode site,
    ast.FunctionBody? body, {
    Iterable<ast.AstNode> initializers = const [],
    void Function(FunctionContext)? initialize,
  }) {
    final target = bindings.target(element, unit, site);
    final extension = bindings.extensionExecutable(element, unit, site);
    final plan = ClosurePlan()
      ..prepare(unit, bindings, target, [
        ...initializers,
        ?body,
      ], receiverType: extension?.receiverType);
    output.add(
      FunctionLowering._(
        unit,
        bindings,
        element,
        site,
        body,
        target,
        plan,
        sourceParameterOffset: extension?.sourceParameterOffset ?? 0,
      )._run(initialize: initialize),
    );
    _appendClosures(output, unit, bindings, plan);
  }

  /// Appends a parameterless initializer and its ordinary lexical closures.
  static void appendExpression(
    List<IrFunction> output,
    ResolvedUnitResult unit,
    Bindings bindings,
    FunctionTarget target,
    ast.Expression expression,
  ) {
    final plan = ClosurePlan()..prepare(unit, bindings, target, [expression]);
    output.add(
      FunctionLowering._(
        unit,
        bindings,
        null,
        expression,
        null,
        target,
        plan,
      )._run(expression: expression),
    );
    _appendClosures(output, unit, bindings, plan);
  }

  static void _appendClosures(
    List<IrFunction> output,
    ResolvedUnitResult unit,
    Bindings bindings,
    ClosurePlan plan,
  ) {
    for (final fn in plan.functions.values) {
      final (element, body, expression) = switch (fn.syntax) {
        ast.FunctionExpression(:final body) => (
          fn.element as LocalFunctionElement,
          body,
          null,
        ),
        ast.VariableDeclaration(:final initializer) => (
          null,
          null,
          initializer,
        ),
        _ => throw StateError('Unexpected lexical body.'),
      };
      output.add(
        FunctionLowering._(
          unit,
          bindings,
          element,
          fn.syntax,
          body,
          fn.target,
          plan,
        )._run(local: fn, expression: expression),
      );
    }
  }

  IrFunction _run({
    LocalClosure? local,
    void Function(FunctionContext)? initialize,
    ast.Expression? expression,
  }) {
    final body = this.body;
    if (body != null && (body.isAsynchronous || body.isGenerator)) {
      unsupported(context.unit, site, 'async or generator bodies');
    }
    context.current = context.addBlock(_target.parameterTypes);
    final inputs = context.current!.parameters;
    if (_target.kind.hasReceiver || sourceParameterOffset != 0) {
      context.receiver = inputs.first;
    }
    if (local != null) {
      if (element != null) context.bindCapture(element!, inputs.first);
      for (final (i, capture) in local.captures.indexed) {
        context.bindCapture(capture, inputs[i + 1]);
      }
    }
    final parameters = element?.formalParameters ?? const [];
    for (final (i, parameter) in parameters.indexed) {
      final input = inputs[i + _target.argumentOffset + sourceParameterOffset];
      context.declare(parameter, input.type, input);
    }
    initialize?.call(context);
    if (expression != null) _return(lowerExpression(context, expression));
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
      defaults: context.bindings.defaults(_target),
    );
  }

  void _return(Value? value) {
    if (context.current == null) return;
    if (value != null) {
      value = context.normal(context.convert(value, _target.returnType));
      if (value == null) return;
    }
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
        lowerVariables(context, variables, (e) => lowerExpression(context, e));
      case ast.FunctionDeclarationStatement(:final functionDeclaration):
        final syntax = functionDeclaration.functionExpression;
        context.bindCapture(
          functionDeclaration.declaredFragment!.element,
          context.close(syntax),
        );
      case ast.PatternVariableDeclarationStatement(:final declaration):
        _patternDeclaration(declaration);
      case ast.ExpressionStatement(:final expression):
        lowerExpression(context, expression);
      case ast.AssertStatement(:final condition, :final message):
        lowerAssert(context, condition, message);
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
    Value? evaluate(ast.Expression expression) =>
        lowerExpression(context, expression);
    void setContinue(void Function() jump) => _continues[statement] = jump;
    switch (statement) {
      case ast.SwitchStatement():
        lowerSwitchStatement(context, statement, exit, _continues, _statement);
      case ast.WhileStatement(:final body, :final condition) ||
          ast.DoStatement(:final body, :final condition):
        lowerLoop(
          context,
          evaluate,
          () => _scoped(body),
          condition,
          exit,
          setContinue: setContinue,
          testAfterBody: statement is ast.DoStatement,
        );
      case ast.ForStatement(
        :final body,
        forLoopParts: final ast.ForParts parts,
      ):
        lowerLoop(
          context,
          evaluate,
          () => _scoped(body),
          parts.condition,
          exit,
          parts: parts,
          setContinue: setContinue,
        );
      case ast.ForStatement(
        forLoopParts: final ast.ForEachParts parts,
        :final body,
      ):
        if (statement.awaitKeyword != null) {
          unsupported(context.unit, statement, 'asynchronous for-in');
        }
        lowerForEach(
          context,
          parts,
          evaluate,
          () => _scoped(body),
          exit,
          setContinue: setContinue,
        );
      default:
        _statement(statement);
    }
    _continues.remove(statement);
    _breaks.remove(statement);
    exit.enter();
  }
}
