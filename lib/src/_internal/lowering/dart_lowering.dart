import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import '../checked_libraries.dart';
import '../ir/ir.dart';

/// Lowers top-level functions from one resolved analysis snapshot.
final class DartLowering {
  final _targets = <TopLevelFunctionElement, FunctionTarget>{};
  final _slots = <FormalParameterElement, int>{};
  DartLowering._();

  static List<IrFunction> lower(CheckedLibraries input) {
    final lowering = DartLowering._();
    return [
      for (final library in input.libraries)
        for (final unit in library.units)
          for (final node in unit.unit.declarations)
            if (node case ast.FunctionDeclaration(
              declaredFragment: TopLevelFunctionFragment(:final element),
              :final functionExpression,
            ))
              _FunctionLowering(
                lowering,
                unit,
                element,
                functionExpression.body,
              ).run()
            else
              _unsupported(unit, node, 'declaration'),
    ];
  }

  FunctionTarget _target(
    TopLevelFunctionElement element,
    ResolvedUnitResult unit,
    ast.AstNode site,
  ) {
    return _targets.putIfAbsent(element, () {
      final parameters = element.formalParameters;
      if (element.typeParameters.isNotEmpty ||
          parameters.any((p) => p.isOptional)) {
        _unsupported(unit, site, 'generic functions or optional parameters');
      }
      for (var i = 0; i < parameters.length; i++) {
        _slots[parameters[i]] = i;
      }
      return FunctionTarget(
        element.library.uri,
        element.name!,
        _type(element.returnType, unit, site, returnType: true),
        parameters.map((p) => _type(p.type, unit, site)),
      );
    });
  }
}

Never _unsupported(ResolvedUnitResult unit, ast.AstNode node, String feature) {
  final location = unit.lineInfo.getLocation(node.offset);
  throw UnsupportedError(
    '${unit.uri}:${location.lineNumber}:${location.columnNumber}: IR lowering for $feature',
  );
}

ValueType _type(
  DartType type,
  ResolvedUnitResult unit,
  ast.AstNode site, {
  bool returnType = false,
}) {
  if (returnType && type is VoidType) return ValueType.voidType;
  if (type.nullabilitySuffix == .none) {
    if (type.isDartCoreInt) return ValueType.integer;
    if (type.isDartCoreBool) return ValueType.boolean;
  }
  _unsupported(unit, site, type.getDisplayString());
}

final class _FunctionLowering {
  final DartLowering library;
  final ResolvedUnitResult unit;
  final TopLevelFunctionElement element;
  final ast.FunctionBody body;
  final _blocks = <Block>[];
  final _values = <VariableElement, Value>{};
  final _locals = <VariableElement>[];
  final _mutable = <VariableElement>[];
  Block? _current;
  late final _target = library._target(element, unit, body);

  _FunctionLowering(this.library, this.unit, this.element, this.body);

  IrFunction run() {
    if (body.isAsynchronous || body.isGenerator) {
      _unsupported(unit, body, 'async or generator bodies');
    }
    _current = _block(_target.parameterTypes);
    for (final (i, parameter) in element.formalParameters.indexed) {
      _declare(parameter, _current!.parameters[i]);
    }
    switch (body) {
      case ast.ExpressionFunctionBody(:final expression):
        _return(_expression(expression));
      case ast.BlockFunctionBody(:final block):
        _statement(block);
        if (_current != null) {
          if (_target.returnType != ValueType.voidType) {
            _unsupported(unit, body, 'implicit return');
          }
          _return(null);
        }
      default:
        _unsupported(unit, body, 'function body');
    }
    return IrFunction(_target, _blocks);
  }

  Block _block([Iterable<ValueType> types = const []]) {
    final block = Block(types);
    _blocks.add(block);
    return block;
  }

  void _return(Value? value) {
    _current!.finish(Return(value));
    _current = null;
  }

  void _declare(VariableElement variable, Value initial) {
    _values[variable] = initial;
    _locals.add(variable);
    if (body.isPotentiallyMutatedInScope(variable)) _mutable.add(variable);
  }

  void _scoped(ast.Statement? statement) {
    final mark = _locals.length;
    final mutableMark = _mutable.length;
    if (statement is ast.Block) {
      for (final child in statement.statements) {
        if (_current == null) break;
        _statement(child);
      }
    } else if (statement != null) {
      _statement(statement);
    }
    while (_locals.length > mark) {
      _values.remove(_locals.removeLast());
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
        _return(expression == null ? null : _expression(expression));
      case ast.VariableDeclarationStatement(:final variables):
        for (final variable in variables.variables) {
          final initializer = variable.initializer;
          if (variable.isLate || initializer == null) {
            _unsupported(unit, variable, 'late or uninitialized locals');
          }
          final local = variable.declaredFragment!.element;
          final type = _type(local.type, unit, variable);
          final value = _expression(initializer);
          if (type != value.type) {
            _unsupported(unit, initializer, 'implicit conversion');
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
                _values.containsKey(writeElement)) {
          final value = _expression(rightHandSide);
          if (value.type != _values[writeElement]!.type) {
            _unsupported(unit, expression, 'implicit conversion');
          }
          _values[writeElement] = value;
        } else {
          _expression(expression);
        }
      case ast.IfStatement(caseClause: null):
        _if(statement);
      case ast.WhileStatement():
        _while(statement);
      default:
        _unsupported(
          unit,
          statement,
          'statement starting with ${statement.beginToken.lexeme}',
        );
    }
  }

  List<Value> _state() => [for (final variable in _mutable) _values[variable]!];

  void _restore(List<Value> state) {
    for (var i = 0; i < _mutable.length; i++) {
      _values[_mutable[i]] = state[i];
    }
  }

  void _if(ast.IfStatement statement) {
    final condition = _expression(statement.expression);
    if (condition case Constant(value: final bool taken)) {
      _scoped(taken ? statement.thenStatement : statement.elseStatement);
      return;
    }
    final yes = _block(), no = _block();
    _current!.finish(Branch(condition, Jump(yes), Jump(no)));
    final before = _state();
    _current = yes;
    _scoped(statement.thenStatement);
    final yesEnd = _current, yesValues = _state();
    _current = no;
    _restore(before);
    _scoped(statement.elseStatement);
    if (yesEnd == null) return;
    if (_current == null) {
      _current = yesEnd;
      _restore(yesValues);
      return;
    }
    final noValues = _state();
    final changed = [
      for (var i = 0; i < _mutable.length; i++)
        if (yesValues[i] != noValues[i]) i,
    ];
    final join = _block(changed.map((i) => yesValues[i].type));
    yesEnd.finish(Jump(join, changed.map((i) => yesValues[i])));
    _current!.finish(Jump(join, changed.map((i) => noValues[i])));
    for (final (p, i) in changed.indexed) {
      _values[_mutable[i]] = join.parameters[p];
    }
    _current = join;
  }

  void _while(ast.WhileStatement statement) {
    final initial = _state();
    final header = _block(initial.map((v) => v.type));
    _current!.finish(Jump(header, initial));
    _current = header;
    _restore(header.parameters);
    final condition = _expression(statement.condition);
    if (condition case Constant(value: false)) return;
    final loop = _block();
    final exit = condition is Constant && condition.value == true
        ? null
        : _block();
    _current!.finish(
      exit == null ? Jump(loop) : Branch(condition, Jump(loop), Jump(exit)),
    );
    _current = loop;
    _scoped(statement.body);
    _current?.finish(Jump(header, _state()));
    _restore(header.parameters);
    _current = exit;
  }

  Value _expression(ast.Expression expression) {
    switch (expression) {
      case ast.BooleanLiteral(:final value):
        return Constant.boolean(value);
      case ast.IntegerLiteral(value: final value?):
        return Constant.integer(value);
      case ast.ParenthesizedExpression(:final expression):
        return _expression(expression);
      case ast.SimpleIdentifier(element: final VariableElement variable)
          when _values.containsKey(variable):
        return _values[variable]!;
      case ast.MethodInvocation(
        methodName: ast.SimpleIdentifier(
          element: final TopLevelFunctionElement callee,
        ),
      ):
        if (expression.target case final receiver?) {
          if (receiver is! ast.SimpleIdentifier ||
              receiver.element is! PrefixElement ||
              (receiver.element as PrefixElement).imports.any(
                (i) => i.prefix?.isDeferred == true,
              )) {
            _unsupported(unit, expression, 'call receiver');
          }
        }
        final target = library._target(callee, unit, expression);
        final values = List<Value?>.filled(target.parameterTypes.length, null);
        for (final argument in expression.argumentList.arguments) {
          final slot = library._slots[argument.correspondingParameter];
          if (slot == null) _unsupported(unit, argument, 'argument binding');
          values[slot] = _expression(argument.argumentExpression);
        }
        return _current!.emit(DirectCall(target, values.cast<Value>()));
      case ast.BinaryExpression(
        :final leftOperand,
        :final rightOperand,
        :final operator,
      ):
        final left = _expression(leftOperand);
        if (operator.lexeme == '&&' || operator.lexeme == '||') {
          final rhs = _block(), join = _block([ValueType.boolean]);
          final evaluate = Jump(rhs), skip = Jump(join, [left]);
          final and = operator.lexeme == '&&';
          _current!.finish(
            Branch(left, and ? evaluate : skip, and ? skip : evaluate),
          );
          _current = rhs;
          final right = _expression(rightOperand);
          _current!.finish(Jump(join, [right]));
          _current = join;
          return join.parameters.single;
        }
        final op = switch (operator.lexeme) {
          '+' => IntOperator.add,
          '-' => IntOperator.subtract,
          '*' => IntOperator.multiply,
          '<' => IntOperator.lessThan,
          _ => _unsupported(unit, expression, operator.lexeme),
        };
        if (left.type != ValueType.integer ||
            _type(rightOperand.staticType!, unit, rightOperand) !=
                ValueType.integer) {
          _unsupported(unit, expression, 'non-integer operator');
        }
        final right = _expression(rightOperand);
        return _current!.emit(IntBinary(op, left, right));
      default:
        _unsupported(
          unit,
          expression,
          'expression starting with ${expression.beginToken.lexeme}',
        );
    }
  }
}
