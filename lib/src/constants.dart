import 'ast.dart';
import 'resolve_type.dart';
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
  List<ConstantValue> elements = const <ConstantValue>[];

  ConstantValue(this.type, this.kind, this.integer, this.text);
}

class ConstantContext {
  SymbolTable symbols;
  List<AstVariable> globals;
  List<int> globalTypes;
  // 0 unseen, 1 visiting, 2 inferred type only, 3 evaluated value.
  List<int> states = <int>[];
  List<ConstantValue> values = <ConstantValue>[];
  List<ConstantValue> locals = <ConstantValue>[];
  List<int> localTypes = <int>[];
  List<ConstantValue> lists = <ConstantValue>[];
  int identical = -1;

  ConstantContext(this.symbols, this.globals, this.globalTypes) {
    var i = 0;
    while (i < globals.length) {
      states.add(0);
      values.add(ConstantValue(-1, tNull, 0, ''));
      i++;
    }
  }
}

ConstantValue constantWithType(ConstantValue value, int type) {
  var result = ConstantValue(type, value.kind, value.integer, value.text);
  result.elements = value.elements;
  return result;
}

Never _constantError(ConstantContext context, int token, String message) {
  var program = context.symbols.program;
  sourceError(program, program.tokens[token], message);
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
  var value = _evaluateConstant(
    context,
    syntax.initializer[0],
    active,
    declared,
    true,
  );
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
  value = constantWithType(value, type);
  context.values[global] = value;
  if (active)
    context.states[global] = 3;
  else
    context.states[global] = 2;
  return value;
}

void checkMetadataConstant(ConstantContext context, AstExpression expression) {
  if (expression.kind == astCall)
    _constantError(
      context,
      expression.token,
      'constructor annotations are unsupported',
    );
  var value = expression.kind == astName && expression.binding >= 0
      ? _evaluateConstant(context, expression, true, -1, true)
      : _constantReference(
          context,
          expression,
          _constantSymbol(context, expression),
          true,
        );
  if (value.type == tVoid)
    _constantError(
      context,
      expression.token,
      'void value cannot be used as metadata',
    );
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
  bool implicitConst,
) {
  var op = expression.text;
  var left = _evaluateConstant(
    context,
    expression.children[0],
    active,
    -1,
    implicitConst,
  );
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
  var right = _evaluateConstant(
    context,
    expression.children[1],
    rightActive,
    -1,
    implicitConst,
  );
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
    var equal = _constantSame(left, right);
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

bool _constantSame(ConstantValue left, ConstantValue right) {
  if (left.kind != right.kind) return false;
  if (left.kind == tString) return left.text == right.text;
  return left.integer == right.integer;
}

ConstantValue _constantCoalescing(
  ConstantContext context,
  AstExpression expression,
  bool active,
  int expected,
  bool implicitConst,
) {
  var left = _evaluateConstant(
    context,
    expression.children[0],
    active,
    expected,
    implicitConst,
  );
  var right = _evaluateConstant(
    context,
    expression.children[1],
    active && left.kind == tNull,
    expected,
    implicitConst,
  );
  var type = typingCoalescing(left.type, right.type);
  if (type < 0) {
    return _constantError(
      context,
      expression.token,
      'void cannot be a null-coalescing receiver',
    );
  }
  if (!active) return ConstantValue(type, tNull, 0, '');
  var value = left;
  if (left.kind == tNull) value = right;
  return constantWithType(value, type);
}

int _constantSymbol(ConstantContext context, AstExpression expression) {
  var prefix = '';
  if (expression.kind == astName) {
    if (expression.binding >= 0) return -1;
  } else if (expression.kind == astMember &&
      expression.children[0].kind == astName &&
      expression.children[0].binding < 0) {
    prefix = expression.children[0].text;
  } else {
    return -1;
  }
  return resolveSymbol(
    context.symbols,
    context.symbols.program.tokens[expression.token].source,
    expression.text,
    prefix,
  );
}

ConstantValue _constantList(
  ConstantContext context,
  AstExpression expression,
  bool active,
  int expected,
  bool implicitConst,
) {
  if (!implicitConst && !expression.constant) {
    return _constantError(
      context,
      expression.token,
      'constant List requires const',
    );
  }
  var element = -1;
  if (expression.typeArguments.isNotEmpty) {
    element = resolveType(context.symbols, expression.typeArguments[0]);
  } else if (expected >= 0 && typeIsList(typeNonNullable(expected))) {
    element = typeArgument(typeNonNullable(expected));
  }
  var elements = <ConstantValue>[];
  var inferred = -1;
  var i = 0;
  while (i < expression.children.length) {
    var child = expression.children[i];
    var value = _evaluateConstant(context, child, active, element, true);
    if (element >= 0 &&
        (!typingAssignable(value.type, element) ||
            active && !typeIsSubtype(value.kind, element))) {
      return _constantError(
        context,
        child.token,
        'invalid constant List element',
      );
    }
    inferred = joinTypes(inferred, value.type);
    elements.add(value);
    i++;
  }
  if (element < 0) element = inferred;
  if (element < 0) element = tDynamic;
  var type = listType(element);
  var result = ConstantValue(type, type, -1, '');
  result.elements = elements;
  if (!active) return result;
  i = 0;
  while (i < context.lists.length) {
    var previous = context.lists[i];
    if (previous.kind == type && previous.elements.length == elements.length) {
      var same = true;
      var item = 0;
      while (same && item < elements.length) {
        same = _constantSame(previous.elements[item], elements[item]);
        item++;
      }
      if (same) return previous;
    }
    i++;
  }
  result.integer = context.lists.length;
  context.lists.add(result);
  return result;
}

ConstantValue _evaluateConstant(
  ConstantContext context,
  AstExpression expression,
  bool active,
  int expected,
  bool implicitConst,
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
  if (kind == astList) {
    return _constantList(context, expression, active, expected, implicitConst);
  }
  if (kind == astName) {
    if (expression.binding >= 0) {
      var binding = expression.binding;
      if (binding >= context.locals.length ||
          context.locals[binding].type < 0) {
        return _constantError(
          context,
          expression.token,
          'constant expression requires an initialized const local',
        );
      }
      return constantWithType(
        context.locals[binding],
        context.localTypes[binding],
      );
    }
    return _constantReference(
      context,
      expression,
      _constantSymbol(context, expression),
      active,
    );
  }
  if (kind == astMember) {
    var receiver = expression.children[0];
    var symbol = _constantSymbol(context, expression);
    if (symbol != -1) {
      return _constantReference(context, expression, symbol, active);
    }
    if (expression.text == 'length') {
      var value = _evaluateConstant(
        context,
        receiver,
        active,
        -1,
        implicitConst,
      );
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
  if (kind == astCall &&
      context.identical >= 0 &&
      _constantSymbol(context, expression.children[0]) == context.identical) {
    if (expression.typeArguments.isNotEmpty ||
        expression.children.length != 3) {
      return _constantError(
        context,
        expression.token,
        'identical requires two arguments and no type arguments',
      );
    }
    var left = _evaluateConstant(
      context,
      expression.children[1],
      active,
      -1,
      implicitConst,
    );
    var right = _evaluateConstant(
      context,
      expression.children[2],
      active,
      -1,
      implicitConst,
    );
    if (left.type == tVoid || right.type == tVoid) {
      return _constantError(
        context,
        expression.token,
        'void is not a constant value',
      );
    }
    if (!active) return ConstantValue(tBool, tNull, 0, '');
    var integer = 0;
    if (_constantSame(left, right)) integer = 1;
    return ConstantValue(tBool, tBool, integer, '');
  }
  if (kind == astUnary) {
    var operand = expression.children[0];
    if (expression.text == '-' && operand.kind == astInteger) {
      return ConstantValue(tInt, tInt, int.parse('-' + operand.text), '');
    }
    var value = _evaluateConstant(context, operand, active, -1, implicitConst);
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
  if (kind == astBinary && expression.text == '??') {
    return _constantCoalescing(
      context,
      expression,
      active,
      expected,
      implicitConst,
    );
  }
  if (kind == astBinary)
    return _constantBinary(context, expression, active, implicitConst);
  if (kind == astConditional) {
    var condition = _evaluateConstant(
      context,
      expression.children[0],
      active,
      tBool,
      implicitConst,
    );
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
      expected,
      implicitConst,
    );
    var elseValue = _evaluateConstant(
      context,
      expression.children[2],
      active && condition.integer == 0,
      expected,
      implicitConst,
    );
    var type = joinTypes(thenValue.type, elseValue.type);
    if (!active) return ConstantValue(type, tNull, 0, '');
    var value = elseValue;
    if (condition.integer != 0) value = thenValue;
    return constantWithType(value, type);
  }
  if (kind == astInterpolation) {
    var text = '';
    var i = 0;
    while (i < expression.children.length) {
      var value = _evaluateConstant(
        context,
        expression.children[i],
        active,
        -1,
        implicitConst,
      );
      if (value.type == tVoid) {
        return _constantError(
          context,
          expression.token,
          'void is not a constant value',
        );
      }
      if (active && typeIsList(value.kind)) {
        return _constantError(
          context,
          expression.token,
          'constant interpolation requires a primitive value',
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
  int expected,
  bool implicitConst,
) {
  return _evaluateConstant(context, expression, true, expected, implicitConst);
}
