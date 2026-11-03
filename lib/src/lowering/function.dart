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
  final _mutable = <VariableElement>[];
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
    if (body.isPotentiallyMutatedInScope(variable)) _mutable.add(variable);
  }

  void _scoped(ast.Statement? statement) {
    final mark = _locals.length;
    final mutableMark = _mutable.length;
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
    _mutable.length = mutableMark;
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
        if (expression
            case ast.AssignmentExpression(
              :final writeElement,
              :final operator,
              :final rightHandSide,
            )
            when operator.lexeme == '=' &&
                writeElement is VariableElement &&
                context.locals.containsKey(writeElement)) {
          final value = lowerExpression(context, rightHandSide);
          if (value.type != context.locals[writeElement]!.type) {
            unsupported(context.unit, expression, 'implicit conversion');
          }
          context.locals[writeElement] = value;
        } else {
          lowerExpression(context, expression);
        }
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

  List<Value> _state() => [
    for (final variable in _mutable) context.locals[variable]!,
  ];

  void _restore(List<Value> state) {
    for (var i = 0; i < _mutable.length; i++) {
      context.locals[_mutable[i]] = state[i];
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
    final before = _state();
    context.current = yes;
    _scoped(statement.thenStatement);
    final yesEnd = context.current, yesValues = _state();
    context.current = no;
    _restore(before);
    _scoped(statement.elseStatement);
    if (yesEnd == null) return;
    if (context.current == null) {
      context.current = yesEnd;
      _restore(yesValues);
      return;
    }
    final noValues = _state();
    final changed = [
      for (var i = 0; i < _mutable.length; i++)
        if (yesValues[i] != noValues[i]) i,
    ];
    final join = context.addBlock(changed.map((i) => yesValues[i].type));
    yesEnd.finish(Jump(join, changed.map((i) => yesValues[i])));
    context.current!.finish(Jump(join, changed.map((i) => noValues[i])));
    for (final (p, i) in changed.indexed) {
      context.locals[_mutable[i]] = join.parameters[p];
    }
    context.current = join;
  }

  void _while(ast.WhileStatement statement) {
    final initial = _state();
    final header = context.addBlock(initial.map((v) => v.type));
    context.current!.finish(Jump(header, initial));
    context.current = header;
    // The condition must read loop-carried values, including on the backedge.
    _restore(header.parameters);
    final condition = lowerExpression(context, statement.condition);
    if (condition case Constant(value: false)) return;
    final loop = context.addBlock();
    final exit = condition is Constant && condition.value == true
        ? null
        : context.addBlock();
    context.current!.finish(
      exit == null ? Jump(loop) : Branch(condition, .new(loop), .new(exit)),
    );
    context.current = loop;
    _scoped(statement.body);
    context.current?.finish(Jump(header, _state()));
    _restore(header.parameters);
    context.current = exit;
  }
}
