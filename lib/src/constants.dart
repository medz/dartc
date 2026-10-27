import 'ast.dart';
import 'arguments.dart';
import 'ir.dart';
import 'members.dart';
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

class ConstantConstructorInfo {
  int classId;
  AstClass owner;
  AstFunction syntax;
  ClassMembers members;
  List<int> fieldTypes;
  List<int> parameterTypes;
  List<int> parameterFields;
  List<int> states = const <int>[];
  List<ConstantValue> values = const <ConstantValue>[];

  ConstantConstructorInfo(
    this.classId,
    this.owner,
    this.syntax,
    this.members,
    this.fieldTypes,
    this.parameterTypes,
    this.parameterFields,
  ) {
    var count = parameterTypes.length + fieldTypes.length;
    states = List<int>.filled(count, 0);
    values = List<ConstantValue>.filled(count, ConstantValue(-1, tNull, 0, ''));
  }
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
  List<ConstantValue> aggregates = <ConstantValue>[];
  List<ConstantConstructorInfo?> constructors = <ConstantConstructorInfo?>[];
  ClassMembers? instanceScope;
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

int constantValueType(ConstantValue value) {
  if (value.kind == tFunction) return functionValueType(value.integer);
  return value.kind;
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
  var scope = context.instanceScope;
  context.instanceScope = null;
  var value = _evaluateConstant(
    context,
    syntax.initializer[0],
    active,
    declared,
    true,
  );
  context.instanceScope = scope;
  var type = declared;
  if (type < 0) {
    type = value.type;
    if (type == tNull) type = tDynamic;
  }
  if (!typingAssignable(value.type, type) ||
      active && !typeIsSubtype(constantValueType(value), type)) {
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

ConstantValue evaluateMetadataConstant(
  ConstantContext context,
  AstExpression expression,
) {
  ConstantValue value;
  if (expression.kind == astCall)
    value = _constantConstructor(context, expression, true, true);
  else if (expression.kind == astName && expression.binding >= 0)
    value = _evaluateConstant(context, expression, true, -1, true);
  else {
    var symbol = _constantSymbol(context, expression);
    if (symbol < 0 || context.symbols.declarations[symbol].kind != symbolGlobal)
      _constantError(
        context,
        expression.token,
        'metadata reference requires an unambiguous const declaration',
      );
    value = _constantGlobal(
      context,
      context.symbols.declarations[symbol].target,
      true,
    );
  }
  if (value.type == tVoid)
    _constantError(
      context,
      expression.token,
      'void value cannot be used as metadata',
    );
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
  if (symbol >= 0) {
    var declaration = context.symbols.declarations[symbol];
    if (declaration.kind == symbolFunction) {
      var type = functionValueType(declaration.target);
      if (type < 0)
        _constantError(
          context,
          expression.token,
          'constant reference to this function shape is not supported',
        );
      return ConstantValue(type, tFunction, declaration.target, '');
    }
  }
  if (symbol < 0 || context.symbols.declarations[symbol].kind != symbolGlobal) {
    return _constantError(
      context,
      expression.token,
      'constant expression requires an unambiguous const or function declaration',
    );
  }
  return _constantGlobal(
    context,
    context.symbols.declarations[symbol].target,
    active,
  );
}

String _constantText(ConstantContext context, ConstantValue value, int token) {
  if (value.kind == tString) return value.text;
  if (value.kind == tNull) return 'null';
  if (value.kind == tBool) {
    if (value.integer != 0) return 'true';
    return 'false';
  }
  if (value.kind == tInt) return value.integer.toString();
  _constantError(
    context,
    token,
    'constant interpolation requires a primitive value',
  );
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
    if (right.kind != tNull && !_constantPrimitiveEquality(context, left))
      _constantError(
        context,
        expression.token,
        'constant equality requires primitive equality',
      );
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
  if (left.kind == tNull) return true;
  if (left.kind == tInt ||
      left.kind == tBool ||
      left.kind == tFunction ||
      typeIsList(left.kind) ||
      typeIsClass(left.kind))
    return left.integer == right.integer;
  return false;
}

bool _constantPrimitiveEquality(ConstantContext context, ConstantValue value) {
  if (!typeIsClass(value.kind)) return true;
  var owner = context.constructors[typeArgument(value.kind)];
  return owner != null &&
      lookupMember(owner.members, '==') < 0 &&
      lookupMember(owner.members, 'hashCode') < 0;
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
  var scope = context.instanceScope;
  var name = expression.text;
  if (prefix != '') name = prefix;
  if (scope != null && lookupMember(scope, name) >= 0)
    _constantError(
      context,
      expression.token,
      'constant expression cannot reference an instance member',
    );
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
            active && !typeIsSubtype(constantValueType(value), element))) {
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
  return _constantAggregate(context, result);
}

ConstantValue _constantAggregate(ConstantContext context, ConstantValue value) {
  var i = 0;
  while (i < context.aggregates.length) {
    var previous = context.aggregates[i];
    if (previous.kind == value.kind &&
        previous.elements.length == value.elements.length) {
      var same = true;
      var item = 0;
      while (same && item < value.elements.length) {
        same = _constantSame(previous.elements[item], value.elements[item]);
        item++;
      }
      if (same) return previous;
    }
    i++;
  }
  value.integer = context.aggregates.length;
  context.aggregates.add(value);
  return value;
}

ConstantValue _constantChecked(
  ConstantContext context,
  ConstantValue value,
  int type,
  int token,
  bool active,
) {
  if (!typingAssignable(value.type, type) ||
      active && !typeIsSubtype(constantValueType(value), type))
    _constantError(context, token, 'incompatible constant value');
  return constantWithType(value, type);
}

ConstantValue _constantDeclaration(
  ConstantContext context,
  ConstantConstructorInfo owner,
  int index,
  bool field,
  bool active,
) {
  var slot = index;
  var type = -1;
  var token = owner.syntax.token;
  AstExpression? expression;
  if (field) {
    slot += owner.parameterTypes.length;
    type = owner.fieldTypes[index];
    var variable = owner.owner.fields[index];
    token = variable.token;
    if (variable.initializer.isNotEmpty) expression = variable.initializer[0];
  } else {
    type = owner.parameterTypes[index];
    token = owner.syntax.parameters[index].token;
    expression = owner.syntax.parameters[index].defaultValue;
  }
  if (!active) return ConstantValue(type, tNull, 0, '');
  if (owner.states[slot] == 3) return owner.values[slot];
  if (owner.states[slot] == 1)
    _constantError(context, token, 'cyclic constant initializer');
  owner.states[slot] = 1;
  var scope = context.instanceScope;
  context.instanceScope = owner.members;
  var value = ConstantValue(tNull, tNull, 0, '');
  if (expression != null)
    value = _evaluateConstant(context, expression, true, type, false);
  context.instanceScope = scope;
  value = _constantChecked(context, value, type, token, true);
  owner.values[slot] = value;
  owner.states[slot] = 3;
  return value;
}

void checkConstantConstructors(ConstantContext context) {
  var c = 0;
  while (c < context.constructors.length) {
    var owner = context.constructors[c];
    if (owner != null) {
      var p = 0;
      while (p < owner.syntax.parameters.length) {
        var parameter = owner.syntax.parameters[p];
        if (parameter.kind != astRequiredPositional && !parameter.required)
          _constantDeclaration(context, owner, p, false, true);
        p++;
      }
      var f = 0;
      while (f < owner.owner.fields.length) {
        if (owner.owner.fields[f].initializer.isNotEmpty)
          _constantDeclaration(context, owner, f, true, true);
        f++;
      }
    }
    c++;
  }
}

ConstantValue _constantConstructor(
  ConstantContext context,
  AstExpression expression,
  bool active,
  bool implicitConst,
) {
  checkArgumentOrder(context.symbols.program, expression);
  var callee = expression.children[0];
  var symbol = _constantSymbol(context, callee);
  if (symbol < 0 || context.symbols.declarations[symbol].kind != symbolClass)
    _constantError(
      context,
      expression.token,
      'constant expression requires a const constructor',
    );
  var classId = context.symbols.declarations[symbol].target;
  ConstantConstructorInfo? owner;
  if (classId < context.constructors.length)
    owner = context.constructors[classId];
  if (owner == null || !expression.constant && !implicitConst)
    _constantError(
      context,
      expression.token,
      'constant constructor requires const',
    );
  if (expression.typeArguments.isNotEmpty || callee.typeArguments.isNotEmpty)
    _constantError(
      context,
      expression.token,
      'nongeneric constructor does not accept type arguments',
    );
  var bindings = bindArguments(
    context.symbols.program,
    owner.syntax,
    expression,
    1,
  );
  var parameters = List<ConstantValue>.filled(
    owner.parameterTypes.length,
    ConstantValue(-1, tNull, 0, ''),
  );
  var i = 1;
  while (i < expression.children.length) {
    var argument = expression.children[i];
    if (argument.kind == astNamedArgument) argument = argument.children[0];
    var parameter = bindings[i - 1];
    var type = owner.parameterTypes[parameter];
    var value = _evaluateConstant(context, argument, active, type, true);
    parameters[parameter] = _constantChecked(
      context,
      value,
      type,
      argument.token,
      active,
    );
    i++;
  }
  i = 0;
  while (i < parameters.length) {
    if (parameters[i].type < 0)
      parameters[i] = _constantDeclaration(context, owner, i, false, active);
    i++;
  }
  var fields = <ConstantValue>[];
  i = 0;
  while (i < owner.fieldTypes.length) {
    fields.add(_constantDeclaration(context, owner, i, true, false));
    i++;
  }
  i = 0;
  while (i < parameters.length) {
    var field = owner.parameterFields[i];
    if (field >= 0)
      fields[field] = _constantChecked(
        context,
        parameters[i],
        owner.fieldTypes[field],
        owner.syntax.parameters[i].token,
        active,
      );
    i++;
  }
  i = 0;
  while (i < fields.length) {
    if (owner.owner.fields[i].initializer.isNotEmpty)
      fields[i] = _constantDeclaration(context, owner, i, true, active);
    i++;
  }
  var type = classType(classId);
  var value = ConstantValue(type, type, -1, '');
  value.elements = fields;
  if (!active) return value;
  return _constantAggregate(context, value);
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
      !expression.constant &&
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
  if (kind == astCall)
    return _constantConstructor(context, expression, active, implicitConst);
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
      if (active &&
          value.kind != tInt &&
          value.kind != tBool &&
          value.kind != tString &&
          value.kind != tNull) {
        return _constantError(
          context,
          expression.token,
          'constant interpolation requires a primitive value',
        );
      }
      if (active) text = text + _constantText(context, value, expression.token);
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
