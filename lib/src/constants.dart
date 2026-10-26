import 'ast.dart';
import 'source.dart';
import 'symbols.dart';
import 'types.dart';
import 'typing.dart';

class ConstantValue {
  // The expression type can be wider than its primitive payload kind.
  int type;
  int kind;
  int integer;
  String text;

  ConstantValue(this.type, this.kind, this.integer, this.text);
}

class ConstantContext {
  SymbolTable symbols;
  List<AstVariable> globals;
  List<int> globalTypes;
  // 0 unseen, 1 visiting, 2 inferred type only, 3 evaluated value.
  List<int> states = <int>[];
  List<ConstantValue> values = <ConstantValue>[];

  ConstantContext(this.symbols, this.globals, this.globalTypes) {
    var i = 0;
    while (i < globals.length) {
      states.add(0);
      values.add(ConstantValue(-1, tNull, 0, ''));
      i++;
    }
  }
}

ConstantValue _constantError(
  ConstantContext context,
  int token,
  String message,
) {
  var program = context.symbols.program;
  sourceError(program, program.tokens[token], message);
  return ConstantValue(tNull, tNull, 0, '');
}

ConstantValue _constantGlobal(
  ConstantContext context,
  int global,
  bool active,
) {
  var syntax = context.globals[global];
  if (syntax.modifier != 'const' || syntax.initializer.isEmpty) {
    return _constantError(
      context,
      syntax.token,
      'constant expression requires a const declaration',
    );
  }
  var declared = context.globalTypes[global];
  // A typed reference in a dead branch does not evaluate its initializer.
  if (!active && declared >= 0) return ConstantValue(declared, tNull, 0, '');
  var state = context.states[global];
  if (state == 3 || !active && state == 2) return context.values[global];
  if (state == 1) {
    return _constantError(
      context,
      syntax.token,
      'cyclic constant ' + syntax.name,
    );
  }
  context.states[global] = 1;
  var value = _evaluateConstant(context, syntax.initializer[0], active);
  var type = declared;
  if (type < 0) {
    type = value.type;
    if (type == tNull) type = tDynamic;
  }
  if (!typingAssignable(value.type, type) ||
      active && !typeIsSubtype(value.kind, type)) {
    return _constantError(
      context,
      syntax.token,
      'invalid const declaration type',
    );
  }
  value = ConstantValue(type, value.kind, value.integer, value.text);
  context.values[global] = value;
  if (active)
    context.states[global] = 3;
  else
    context.states[global] = 2;
  return value;
}

ConstantValue evaluateGlobalConstant(ConstantContext context, int global) {
  return _constantGlobal(context, global, true);
}

ConstantValue _constantReference(
  ConstantContext context,
  AstExpression expression,
  int symbol,
  bool active,
) {
  if (symbol < 0 || context.symbols.declarations[symbol].kind != symbolGlobal) {
    return _constantError(
      context,
      expression.token,
      'constant expression requires an unambiguous const declaration',
    );
  }
  return _constantGlobal(
    context,
    context.symbols.declarations[symbol].target,
    active,
  );
}

String _constantText(ConstantValue value) {
  if (value.kind == tString) return value.text;
  if (value.kind == tNull) return 'null';
  if (value.kind == tBool) {
    if (value.integer != 0) return 'true';
    return 'false';
  }
  return value.integer.toString();
}

ConstantValue _constantBinary(
  ConstantContext context,
  AstExpression expression,
  bool active,
) {
  var op = expression.text;
  var left = _evaluateConstant(context, expression.children[0], active);
  var rightActive = active;
  var logical = op == '&&' || op == '||';
  if (logical && active) {
    if (left.kind != tBool) {
      return _constantError(
        context,
        expression.token,
        'constant condition must be bool',
      );
    }
    if (op == '&&' && left.integer == 0 || op == '||' && left.integer != 0) {
      rightActive = false;
    }
  }
  var right = _evaluateConstant(context, expression.children[1], rightActive);
  var type = typingBinary(op, left.type, right.type);
  if (type < 0) {
    return _constantError(
      context,
      expression.token,
      'invalid constant operator ' + op,
    );
  }
  if (!active) return ConstantValue(type, tNull, 0, '');
  var integer = 0;
  if (logical) {
    if (!rightActive) return ConstantValue(type, tBool, left.integer, '');
    if (right.kind != tBool) {
      return _constantError(
        context,
        expression.token,
        'constant condition must be bool',
      );
    }
    return ConstantValue(type, tBool, right.integer, '');
  }
  if (op == '==' || op == '!=') {
    var equal = left.kind == right.kind;
    if (equal && left.kind == tString)
      equal = left.text == right.text;
    else if (equal)
      equal = left.integer == right.integer;
    if (op == '!=') equal = !equal;
    if (equal) integer = 1;
    return ConstantValue(type, tBool, integer, '');
  }
  var kind = typingBinary(op, left.kind, right.kind);
  if (kind < 0) {
    return _constantError(
      context,
      expression.token,
      'invalid constant operand value',
    );
  }
  if (kind == tString) {
    return ConstantValue(type, tString, 0, left.text + right.text);
  }
  var a = left.integer;
  var b = right.integer;
  if ((op == '~/' || op == '%') && b == 0) {
    return _constantError(
      context,
      expression.token,
      'constant division by zero',
    );
  }
  if ((op == '<<' || op == '>>' || op == '>>>') && b < 0) {
    return _constantError(context, expression.token, 'negative constant shift');
  }
  if (op == '+') integer = a + b;
  if (op == '-') integer = a - b;
  if (op == '*') integer = a * b;
  if (op == '~/') integer = a ~/ b;
  if (op == '%') integer = a % b;
  if (op == '&') integer = a & b;
  if (op == '|') integer = a | b;
  if (op == '^') integer = a ^ b;
  if (op == '<<') integer = a << b;
  if (op == '>>') integer = a >> b;
  if (op == '>>>') integer = a >>> b;
  if (op == '<' && a < b ||
      op == '<=' && a <= b ||
      op == '>' && a > b ||
      op == '>=' && a >= b) {
    integer = 1;
  }
  return ConstantValue(type, kind, integer, '');
}

ConstantValue _evaluateConstant(
  ConstantContext context,
  AstExpression expression,
  bool active,
) {
  var kind = expression.kind;
  if (kind == astInteger) {
    return ConstantValue(tInt, tInt, int.parse(expression.text), '');
  }
  if (kind == astBoolean) {
    var integer = 0;
    if (expression.text == 'true') integer = 1;
    return ConstantValue(tBool, tBool, integer, '');
  }
  if (kind == astString)
    return ConstantValue(tString, tString, 0, expression.text);
  if (kind == astNull) return ConstantValue(tNull, tNull, 0, '');
  if (kind == astName) {
    return _constantReference(
      context,
      expression,
      resolveSymbol(
        context.symbols,
        context.symbols.program.tokens[expression.token].source,
        expression.text,
        '',
      ),
      active,
    );
  }
  if (kind == astMember) {
    var receiver = expression.children[0];
    if (receiver.kind == astName) {
      var symbol = resolveSymbol(
        context.symbols,
        context.symbols.program.tokens[expression.token].source,
        expression.text,
        receiver.text,
      );
      if (symbol != -1) {
        return _constantReference(context, expression, symbol, active);
      }
    }
    if (expression.text == 'length') {
      var value = _evaluateConstant(context, receiver, active);
      if (value.type == tString || value.type == tDynamic) {
        var type = tInt;
        if (value.type == tDynamic) type = tDynamic;
        if (!active) return ConstantValue(type, tNull, 0, '');
        if (value.kind == tString) {
          return ConstantValue(type, tInt, value.text.length, '');
        }
      }
    }
    return _constantError(
      context,
      expression.token,
      'unsupported constant property',
    );
  }
  if (kind == astUnary) {
    var operand = expression.children[0];
    if (expression.text == '-' && operand.kind == astInteger) {
      return ConstantValue(tInt, tInt, int.parse('-' + operand.text), '');
    }
    var value = _evaluateConstant(context, operand, active);
    var type = typingUnary(expression.text, value.type);
    if (type < 0) {
      return _constantError(
        context,
        expression.token,
        'invalid constant unary operator',
      );
    }
    if (!active) return ConstantValue(type, tNull, 0, '');
    var valueKind = typingUnary(expression.text, value.kind);
    if (valueKind < 0) {
      return _constantError(
        context,
        expression.token,
        'invalid constant unary value',
      );
    }
    var integer = value.integer;
    if (expression.text == '-') integer = -integer;
    if (expression.text == '~') integer = ~integer;
    if (expression.text == '!') integer = 1 - integer;
    return ConstantValue(type, valueKind, integer, '');
  }
  if (kind == astBinary) return _constantBinary(context, expression, active);
  if (kind == astConditional) {
    var condition = _evaluateConstant(context, expression.children[0], active);
    if (!typingCondition(condition.type) || active && condition.kind != tBool) {
      return _constantError(
        context,
        expression.token,
        'constant condition must be bool',
      );
    }
    var thenValue = _evaluateConstant(
      context,
      expression.children[1],
      active && condition.integer != 0,
    );
    var elseValue = _evaluateConstant(
      context,
      expression.children[2],
      active && condition.integer == 0,
    );
    var type = joinTypes(thenValue.type, elseValue.type);
    if (!active) return ConstantValue(type, tNull, 0, '');
    var value = elseValue;
    if (condition.integer != 0) value = thenValue;
    return ConstantValue(type, value.kind, value.integer, value.text);
  }
  if (kind == astInterpolation) {
    var text = '';
    var i = 0;
    while (i < expression.children.length) {
      var value = _evaluateConstant(context, expression.children[i], active);
      if (value.type == tVoid) {
        return _constantError(
          context,
          expression.token,
          'void is not a constant value',
        );
      }
      if (active) text = text + _constantText(value);
      i++;
    }
    return ConstantValue(tString, tString, 0, text);
  }
  return _constantError(
    context,
    expression.token,
    'unsupported constant expression',
  );
}

ConstantValue evaluateConstant(
  ConstantContext context,
  AstExpression expression,
) {
  return _evaluateConstant(context, expression, true);
}
