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

/// Builds blocks and local bindings for ordinary and suspendable function bodies.
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
  late final FunctionContext context;

  this {
    context = .new(
      unit,
      bindings,
      element is ConstructorElement || body == null
          ? (variable) => !variable.isFinal
          : body!.isPotentiallyMutatedInScope,
      plan,
      _target,
      isAsynchronous: body?.isAsynchronous == true,
      withFinally: _protect,
    );
  }
  bool get _representationConstructor =>
      element is ConstructorElement &&
      !(element as ConstructorElement).isFactory &&
      element!.enclosingElement is ExtensionTypeElement;

  final _breaks = <ast.AstNode, JumpTarget>{};
  final _continues = <ast.AstNode, void Function()>{};
  FinallyRegion? _finally;
  ValueType? get _yieldType {
    if (body?.isGenerator != true) return null;
    var type = _target.returnType.nonNullable;
    while (type is FutureOrType) {
      type = type.argument;
    }
    return CoreTypes.view(
          type,
          context.isAsynchronous ? CoreTypes.stream : CoreTypes.iterable,
        )?.typeArguments.single ??
        ValueType.dynamicType;
  }

  late final ValueType? _completionType =
      context.isAsynchronous && _yieldType == null
      ? context.typeOf(
          context.unit.typeSystem.futureValueType(element!.returnType),
          site,
        )
      : null;
  ValueType get _bodyReturnType => _completionType != null
      ? ValueType.futureOr(_completionType)
      : _yieldType == null
      ? _target.returnType
      : ValueType.nullType;

  /// Appends the outer graph and the lexical bodies it declares to [output].
  static void append(
    List<IrCallable> output,
    ResolvedUnitResult unit,
    Bindings bindings,
    ExecutableElement element,
    ast.AstNode site,
    ast.FunctionBody? body, {
    Iterable<ast.AstNode> initializers = const [],
    void Function(FunctionContext)? initialize,
    FunctionTarget? destination,
  }) {
    final target = destination ?? bindings.target(element, unit, site);
    if (element.isExternal) {
      if (element.library.isDartCore &&
          element.baseElement ==
              element.library.getTopLevelFunction('identical')) {
        final entry = Block(target.parameterTypes);
        entry.finish(
          Return(
            entry.emit(Identical(entry.parameters[0], entry.parameters[1])),
          ),
        );
        output.add(IrFunction(target, [entry]));
        return;
      }
      output.add(IrExternal(target, defaults: bindings.defaults(target)));
      return;
    }
    final extension = bindings.extensionExecutable(element, unit, site);
    final plan = ClosurePlan()
      ..prepare(
        unit,
        bindings,
        target,
        [...initializers, ?body],
        receiverType:
            extension?.receiverType ??
            (element is ConstructorElement &&
                    !element.isFactory &&
                    element.enclosingElement is ExtensionTypeElement
                ? target.returnType
                : null),
      );
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
    List<IrCallable> output,
    ResolvedUnitResult unit,
    Bindings bindings,
    FunctionTarget target,
    ast.Expression expression,
  ) => appendInitializer(output, unit, bindings, target, expression, [
    expression,
  ], (context) => lowerExpression(context, expression));

  /// Appends an ordinary initializer from resolved initialization expressions.
  static void appendInitializer(
    List<IrCallable> output,
    ResolvedUnitResult unit,
    Bindings bindings,
    FunctionTarget target,
    ast.AstNode site,
    Iterable<ast.AstNode> expressions,
    Value? Function(FunctionContext) evaluate,
  ) {
    final plan = ClosurePlan()..prepare(unit, bindings, target, expressions);
    final function = FunctionLowering._(
      unit,
      bindings,
      null,
      site,
      null,
      target,
      plan,
    );
    output.add(
      function._run(
        initialize: (context) => function._return(evaluate(context)),
      ),
    );
    _appendClosures(output, unit, bindings, plan);
  }

  static void _appendClosures(
    List<IrCallable> output,
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
    output.addAll(plan.adapters.values);
  }

  IrFunction _run({
    LocalClosure? local,
    void Function(FunctionContext)? initialize,
    ast.Expression? expression,
  }) {
    final body = this.body;
    final yieldType = _yieldType;
    if (yieldType != null &&
        !_target.returnType.accepts(
          context.isAsynchronous
              ? CoreTypes.streamOf(yieldType)
              : CoreTypes.iterableOf(yieldType),
        )) {
      unsupported(context.unit, site, 'generator result type');
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
        case null || ast.EmptyFunctionBody()
            when _target.kind == .initializer || _representationConstructor:
          _return(null);
        case ast.ExpressionFunctionBody(:final expression):
          _return(lowerExpression(context, expression));
        case ast.BlockFunctionBody(:final block):
          _statement(block);
          if (context.current != null) {
            if (!_representationConstructor &&
                !_bodyReturnType.accepts(.nullType)) {
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
      bodyKind: switch ((context.isAsynchronous, _yieldType)) {
        (true, null) => .asynchronous,
        (true, _) => .asyncGenerator,
        (false, null) => .synchronous,
        (false, _) => .syncGenerator,
      },
      yieldType: _yieldType,
      completionType: _completionType,
    );
  }

  void _return(Value? value) {
    if (context.current == null) return;
    if (_representationConstructor) value ??= context.receiver;
    if (value != null) {
      value = context.normal(context.convert(value, _bodyReturnType));
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
    _protect(statement, body, () => _scoped(finalizer));
  }

  void _protect(
    ast.AstNode scope,
    void Function() body,
    void Function() cleanup,
  ) {
    final enclosing = _finally;
    final region = FinallyRegion(context, scope, _bodyReturnType);
    region.lower(
      () {
        _finally = region;
        body();
        _finally = enclosing;
      },
      cleanup,
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

  void _yield(ast.YieldStatement statement) {
    final type = _yieldType;
    if (type == null) unsupported(context.unit, statement, 'yield body');
    var value = lowerExpression(context, statement.expression);
    if (value == null) return;
    if (statement.star == null) {
      value = context.normal(context.convert(value, type));
      if (value != null) _suspend(value);
      return;
    }
    if (context.isAsynchronous) {
      value = context.normal(context.convert(value, CoreTypes.streamOf(type)));
      if (value != null) _suspend(value, delegate: true);
      return;
    }
    // Unlike a for-in loop, yield* checks the complete Iterable<T> before
    // requesting its iterator, even when the iterable is empty.
    value = context.normal(context.convert(value, CoreTypes.iterableOf(type)));
    if (value == null) return;
    final iterator = context.emit(GetIterator(value));
    final header = JumpTarget(context)
      ..jump()
      ..enter();
    final done = JumpTarget(context);
    context.guard(context.emit(IteratorMoveNext(iterator)), done);
    final current = context.normal(context.emit(IteratorCurrent(iterator)));
    if (current != null) {
      _suspend(current);
      header.jump();
    }
    done.enter();
  }

  void _suspend(Value value, {bool delegate = false}) {
    final next = JumpTarget(context);
    final cancel = context.isAsynchronous ? JumpTarget(context) : null;
    context.current!.finish(
      delegate
          ? YieldStream(
              value,
              next.edge(),
              onCancel: cancel!.edge(),
              onThrow: context.handler?.edge([
                UnwindValue.exception,
                UnwindValue.stackTrace,
              ]),
            )
          : Yield(value, next.edge(), onCancel: cancel?.edge()),
    );
    context.current = null;
    if (cancel?.enter() != null) _return(null);
    next.enter();
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
      case ast.YieldStatement():
        _yield(statement);
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
        _jump(
          statement is ast.ContinueStatement && target is ast.ForStatement
              ? target.body
              : target!,
          jump,
        );
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
