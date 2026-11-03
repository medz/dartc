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
  late final _target = context.bindings.target(element, context.unit, body);

  /// Lowers the body and verifies the resulting function before returning it.
  IrFunction run() {
    if (body.isAsynchronous || body.isGenerator) {
      unsupported(context.unit, body, 'async or generator bodies');
    }
    context.current = context.addBlock(_target.parameterTypes);
    for (final (i, parameter) in element.formalParameters.indexed) {
      _declare(parameter, context.current!.parameters[i]);
    }
    switch (body) {
      case ast.ExpressionFunctionBody(:final expression):
        _return(lowerExpression(context, expression));
      case ast.BlockFunctionBody(:final block):
        _statement(block);
        if (context.current != null) {
          if (_target.returnType != .voidType) {
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

  void _declare(VariableElement variable, Value initial) {
    context.locals[variable] = initial;
    _locals.add(variable);
    if (body.isPotentiallyMutatedInScope(variable)) {
      context.mutableLocals.add(variable);
    }
  }

  void _scoped(ast.Statement? statement) {
    final mark = _locals.length;
    final mutableMark = context.mutableLocals.length;
    if (statement is ast.Block) {
      for (final child in statement.statements) {
        if (context.current == null) break;
        _statement(child);
      }
    } else if (statement != null) {
      _statement(statement);
    }
    while (_locals.length > mark) {
      context.locals.remove(_locals.removeLast());
    }
    context.mutableLocals.length = mutableMark;
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
        for (final variable in variables.variables) {
          final initializer = variable.initializer;
          if (variable.isLate || initializer == null) {
            unsupported(context.unit, variable, 'late or uninitialized locals');
          }
          final local = variable.declaredFragment!.element;
          final type = valueType(local.type, context.unit, variable);
          final value = lowerExpression(context, initializer);
          if (type != value.type) {
            unsupported(context.unit, initializer, 'implicit conversion');
          }
          _declare(local, value);
        }
      case ast.ExpressionStatement(:final expression):
        lowerExpression(context, expression);
      case ast.IfStatement(caseClause: null):
        _if(statement);
      case ast.WhileStatement():
        _while(statement);
      default:
        unsupported(
          context.unit,
          statement,
          'statement starting with ${statement.beginToken.lexeme}',
        );
    }
  }

  void _if(ast.IfStatement statement) {
    final condition = lowerExpression(context, statement.expression);
    if (condition case Constant(value: final bool taken)) {
      _scoped(taken ? statement.thenStatement : statement.elseStatement);
      return;
    }
    final yes = context.addBlock(), no = context.addBlock();
    context.current!.finish(Branch(condition, .new(yes), .new(no)));
    final before = context.saveLocals();
    context.current = yes;
    _scoped(statement.thenStatement);
    final yesEnd = context.current, yesValues = context.saveLocals();
    context.current = no;
    context.restoreLocals(before);
    _scoped(statement.elseStatement);
    if (yesEnd == null) return;
    final noEnd = context.current;
    if (noEnd == null) {
      context.current = yesEnd;
      context.restoreLocals(yesValues);
      return;
    }
    final (fromYes, fromNo) = context.join(yesValues);
    yesEnd.finish(fromYes);
    noEnd.finish(fromNo);
  }

  void _while(ast.WhileStatement statement) {
    final initial = context.saveLocals();
    final header = context.addBlock(initial.map((v) => v.type));
    context.current!.finish(Jump(header, initial));
    context.current = header;
    // The condition must read loop-carried values, including on the backedge.
    context.restoreLocals(header.parameters);
    final condition = lowerExpression(context, statement.condition);
    if (condition case Constant(value: false)) return;
    final loop = context.addBlock();
    final exit = condition is Constant && condition.value == true
        ? null
        : context.addBlock();
    context.current!.finish(
      exit == null ? Jump(loop) : Branch(condition, .new(loop), .new(exit)),
    );
    final afterCondition = exit == null ? null : context.saveLocals();
    context.current = loop;
    _scoped(statement.body);
    context.current?.finish(Jump(header, context.saveLocals()));
    if (afterCondition != null) context.restoreLocals(afterCondition);
    context.current = exit;
  }
}
