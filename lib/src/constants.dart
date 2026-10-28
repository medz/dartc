import 'ast.dart';
import 'binary64.dart';
import 'host.dart';
import 'frontend/arguments.dart';
import 'frontend/literals.dart';
import 'initialization.dart';
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

class ConstructorConstants {
  int classId;
  AstClass owner;
  AstFunction syntax;
  List<int> fieldTypes;
  List<int> parameterTypes;
  ConstructorPlan plan;
  List<int> states = const <int>[];
  List<ConstantValue> values = const <ConstantValue>[];

  ConstructorConstants(
    this.classId,
    this.owner,
    this.syntax,
    this.fieldTypes,
    this.parameterTypes,
    this.plan,
  ) {
    var count = parameterTypes.length + fieldTypes.length;
    states = List<int>.filled(count, 0);
    values = List<ConstantValue>.filled(count, ConstantValue(-1, tNull, 0, ''));
  }
}

class _ConstantInvocation {
  final ConstructorConstants owner;
  final List<ConstantValue> parameters;

  _ConstantInvocation(this.owner, this.parameters);
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
  ConstantValue? implicitReceiver;
  List<int> typeScope = const <int>[];
  List<ConstantValue> initializerParameters = const <ConstantValue>[];
  bool allowInitializerParameters = false;
  List<ConstantValue> aggregates = <ConstantValue>[];
  List<ConstructorConstants?> constructors = <ConstructorConstants?>[];
  List<_ConstantInvocation> invocations = <_ConstantInvocation>[];
  List<ClassMembers> classMembers = const <ClassMembers>[];
  List<List<int>> classConstructors = const <List<int>>[];
  int lexicalClass = -1;
  List<int> globalOwners = const <int>[];
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
  var scope = context.lexicalClass;
  var typeScope = context.typeScope;
  var parameters = context.initializerParameters;
  context.lexicalClass = context.globalOwners[global];
  context.typeScope = const <int>[];
  context.initializerParameters = const <ConstantValue>[];
  var value = _evaluateConstant(
    context,
    syntax.initializer[0],
    active,
    declared,
    true,
  );
  context.lexicalClass = scope;
  context.typeScope = typeScope;
  context.initializerParameters = parameters;
  var type = declared;
  if (type < 0) {
    type = value.type;
    if (type == tNull) type = tDynamic;
  }
  value = _constantImplicitCall(context, value, type, syntax.token, active);
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
    var owner = _constantStaticOwner(context, expression);
    if (owner >= 0) {
      value = _constantStaticReference(context, expression, owner, true, true);
    } else {
      var symbol = _constantSymbol(context, expression);
      if (symbol < 0 ||
          context.symbols.declarations[symbol].kind != symbolGlobal)
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
  if (value.kind == tDouble) return binary64Format(value.integer);
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
  int expected,
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
    typingBinaryContext(op, left.type, expected),
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
    if ((left.kind == tInt || left.kind == tDouble) &&
        (right.kind == tInt || right.kind == tDouble)) {
      if (left.kind == tDouble || right.kind == tDouble)
        equal =
            hostFloat64Compare(_constantDouble(left), _constantDouble(right)) ==
            0;
    }
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
  if (left.kind == tDouble || right.kind == tDouble || op == '/') {
    final a = _constantDouble(left);
    final b = _constantDouble(right);
    if (op == '+') integer = hostFloat64Add(a, b);
    if (op == '-') integer = hostFloat64Sub(a, b);
    if (op == '*') integer = hostFloat64Mul(a, b);
    if (op == '/') integer = hostFloat64Div(a, b);
    if (op == '%') integer = binary64Modulo(a, b);
    if (op == '~/') {
      final quotient = hostFloat64Div(a, b);
      if ((quotient & 0x7fffffffffffffff) >= binary64Infinity)
        _constantError(
          context,
          expression.token,
          'non-finite constant integer division',
        );
      integer = hostFloat64ToInt(quotient);
    }
    if (kind == tBool) {
      final comparison = hostFloat64Compare(a, b);
      final result = switch (op) {
        '<' => comparison == -1,
        '<=' => comparison <= 0,
        '>' => comparison == 1,
        _ => comparison == 0 || comparison == 1,
      };
      integer = result ? 1 : 0;
    }
    return ConstantValue(type, kind, integer, '');
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

int _constantDouble(ConstantValue value) =>
    value.kind == tInt ? hostFloat64FromInt(value.integer) : value.integer;

bool _constantSame(ConstantValue left, ConstantValue right) {
  if (left.kind != right.kind) return false;
  if (left.kind == tString) return left.text == right.text;
  if (left.kind == tNull) return true;
  if (left.kind == tDouble)
    return left.integer == right.integer ||
        binary64IsNaN(left.integer) && binary64IsNaN(right.integer);
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
  var owner = context.classMembers[typeArgument(value.kind)];
  return lookupMember(owner, '==') < 0 && lookupMember(owner, 'hashCode') < 0;
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
  var scope = context.lexicalClass;
  var name = expression.text;
  if (prefix != '') name = prefix;
  if (context.typeScope.isNotEmpty &&
      typeParameterInScope(context.typeScope, name) >= 0)
    _constantError(
      context,
      expression.token,
      'type parameter is not a constant declaration',
    );
  if (scope >= 0 && lookupMember(context.classMembers[scope], name) >= 0)
    return -1;
  return resolveSymbol(
    context.symbols,
    context.symbols.program.tokens[expression.token].source,
    expression.text,
    prefix,
  );
}

int _constantStaticOwner(ConstantContext context, AstExpression expression) {
  if (expression.kind == astName && expression.binding < 0) {
    var owner = context.lexicalClass;
    if (owner >= 0 &&
        lookupMember(context.classMembers[owner], expression.text) >= 0)
      return owner;
  } else if (expression.kind == astMember) {
    var receiver = expression.children[0];
    var symbol = _constantSymbol(context, receiver);
    var owner = declarationClassOwner(context.symbols, symbol);
    if (owner >= 0) {
      if (receiver.typeArguments.isNotEmpty)
        _constantError(
          context,
          receiver.token,
          'static member qualifier does not accept type arguments',
        );
      return owner;
    }
  }
  return -1;
}

int _constantType(ConstantContext context, AstType syntax) {
  var type = resolveType(context.symbols, syntax, context.typeScope);
  if (typeContainsParameters(type))
    _constantError(
      context,
      syntax.token,
      'constant type cannot depend on a type parameter',
    );
  return type;
}

int _constantConstructorType(
  ConstantContext context,
  int symbol,
  List<AstType> arguments,
  int token,
) {
  if (symbol < 0) return -1;
  var declaration = context.symbols.declarations[symbol];
  if (declaration.kind != symbolClass && declaration.kind != symbolAlias)
    return -1;
  var type = resolveDeclarationType(
    context.symbols,
    symbol,
    arguments,
    token,
    context.typeScope,
    false,
  );
  if (declaration.kind == symbolAlias &&
      context.symbols.aliases[declaration.target].expandsToParameter)
    _constantError(
      context,
      token,
      'type parameter alias has no constructor namespace',
    );
  if (typeContainsParameters(type))
    _constantError(
      context,
      token,
      'constant type cannot depend on a type parameter',
    );
  return type;
}

ConstantValue _constantStaticReference(
  ConstantContext context,
  AstExpression expression,
  int owner,
  bool active,
  bool metadata,
) {
  if (expression.typeArguments.isNotEmpty)
    _constantError(
      context,
      expression.token,
      'type application values are unsupported',
    );
  var index = lookupMember(context.classMembers[owner], expression.text);
  if (index < 0)
    _constantError(context, expression.token, 'unknown static member');
  var member = context.classMembers[owner].members[index];
  if (!member.isStatic)
    _constantError(
      context,
      expression.token,
      'constant expression cannot reference an instance member',
    );
  var source = context.symbols.program;
  var declarationSource = sourceUnknown;
  var global = -1;
  var function = -1;
  if (member.staticField >= 0) {
    global = member.staticField;
    declarationSource = source.tokens[context.globals[global].token].source;
  } else {
    var method = member.method;
    if (method < 0) method = member.getter;
    if (method < 0) method = member.setter;
    function = method;
    declarationSource = functions[function].source;
  }
  if (member.name.startsWith('_') &&
      sourceLibrary(source, source.tokens[expression.token].source) !=
          sourceLibrary(source, declarationSource))
    _constantError(
      context,
      expression.token,
      'private member is not accessible',
    );
  if (global >= 0) return _constantGlobal(context, global, active);
  if (member.method >= 0 && !metadata) {
    var type = functionValueType(function);
    if (type < 0)
      _constantError(
        context,
        expression.token,
        'constant reference to this function shape is not supported',
      );
    return ConstantValue(type, tFunction, function, '');
  }
  _constantError(
    context,
    expression.token,
    'constant expression requires a const declaration',
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
    element = _constantType(context, expression.typeArguments[0]);
  } else if (expected >= 0 && typeIsList(typeNonNullable(expected))) {
    element = typeArgument(typeNonNullable(expected));
  }
  var elements = <ConstantValue>[];
  var inferred = -1;
  var allowParameters = context.allowInitializerParameters;
  context.allowInitializerParameters = false;
  for (var child in expression.children) {
    inferred = joinTypes(
      inferred,
      _constantListElement(context, child, active, element, elements),
    );
  }
  context.allowInitializerParameters = allowParameters;
  if (element < 0)
    element = inferred;
  else
    element = typeCompleteSchema(element, inferred);
  if (element < 0) element = tDynamic;
  var type = listType(element);
  var result = ConstantValue(type, type, -1, '');
  result.elements = elements;
  if (!active) return result;
  return _constantAggregate(context, result);
}

int _constantListElement(
  ConstantContext context,
  AstExpression expression,
  bool active,
  int expected,
  List<ConstantValue> elements,
) {
  if (expression.kind == astForElement)
    _constantError(context, expression.token, 'for element is not constant');
  if (expression.kind == astNullAwareElement) {
    var program = context.symbols.program;
    if (!sourceVersionAtLeast(
      program,
      program.tokens[expression.token].source,
      3,
      8,
    ))
      _constantError(
        context,
        expression.token,
        'null-aware elements require language version 3.8',
      );
    var hint = expected;
    if (hint >= 0 && hint != tVoid) hint = nullableType(hint);
    var value = _evaluateConstant(
      context,
      expression.children[0],
      active,
      hint,
      true,
    );
    value = _constantImplicitCall(
      context,
      value,
      hint,
      expression.token,
      active,
    );
    var type = typingNonNull(value.type);
    if (expected >= 0 && !typingAssignable(type, expected))
      _constantError(
        context,
        expression.token,
        'invalid constant List element',
      );
    if (active && value.kind != tNull) {
      if (expected >= 0 && !typeIsSubtype(constantValueType(value), expected))
        _constantError(
          context,
          expression.token,
          'invalid constant List element',
        );
      elements.add(value);
    }
    return type;
  }
  if (expression.kind == astIfElement) {
    if (expression.children[0].kind == astIfCaseCondition)
      _constantError(
        context,
        expression.token,
        'constant if-case elements are not supported',
      );
    var condition = _evaluateConstant(
      context,
      expression.children[0],
      active,
      tBool,
      true,
    );
    if (!typingCondition(condition.type) || active && condition.kind != tBool)
      _constantError(
        context,
        expression.token,
        'collection condition requires bool',
      );
    var truth = condition.integer != 0;
    var type = _constantListElement(
      context,
      expression.children[1],
      active && truth,
      expected,
      elements,
    );
    if (expression.children.length == 3)
      type = joinTypes(
        type,
        _constantListElement(
          context,
          expression.children[2],
          active && !truth,
          expected,
          elements,
        ),
      );
    return type;
  }
  if (expression.kind == astSpreadElement) {
    var hint = expected < 0 ? -1 : listType(expected);
    var value = _evaluateConstant(
      context,
      expression.children[0],
      active,
      hint,
      true,
    );
    var nullAware = expression.text == '...?';
    var type = typingIterableElement(value.type, nullAware);
    if (type < 0 || expected >= 0 && !typingAssignable(type, expected))
      _constantError(
        context,
        expression.token,
        'invalid constant spread element type',
      );
    if (!active || nullAware && value.kind == tNull) return type;
    if (!typeIsList(value.kind))
      _constantError(
        context,
        expression.token,
        'constant spread requires a constant collection',
      );
    for (var element in value.elements) {
      if (expected >= 0 && !typeIsSubtype(constantValueType(element), expected))
        _constantError(
          context,
          expression.token,
          'invalid constant List element',
        );
      elements.add(element);
    }
    return type;
  }
  var value = _evaluateConstant(context, expression, active, expected, true);
  value = _constantImplicitCall(
    context,
    value,
    expected,
    expression.token,
    active,
  );
  if (expected >= 0 &&
      (!typingAssignable(value.type, expected) ||
          active && !typeIsSubtype(constantValueType(value), expected)))
    _constantError(context, expression.token, 'invalid constant List element');
  if (active) elements.add(value);
  return value.type;
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

ConstantValue _constantImplicitCall(
  ConstantContext context,
  ConstantValue value,
  int expected,
  int token,
  bool active,
) {
  if (expected < 0 || !typeIsClass(value.type)) return value;
  var target = typeNonNullable(expected);
  if (!typeIsFunction(target) && target != tFunction) return value;
  var owner = typeArgument(value.type);
  var members = context.classMembers[owner];
  var index = lookupMember(members, 'call');
  if (index < 0) return value;
  var member = members.members[index];
  if (member.isStatic || member.method < 0) return value;
  var type = functionValueType(member.method);
  if (type < 0)
    _constantError(context, token, 'unsupported callable signature');
  if (active)
    _constantError(context, token, 'implicit call tear-off is not constant');
  return ConstantValue(type, tNull, 0, '');
}

ConstantValue _constantChecked(
  ConstantContext context,
  ConstantValue value,
  int type,
  int token,
  bool active,
) {
  value = _constantImplicitCall(context, value, type, token, active);
  if (!typingAssignable(value.type, type) ||
      active && !typeIsSubtype(constantValueType(value), type))
    _constantError(context, token, 'incompatible constant value');
  return constantWithType(value, type);
}

ConstantValue _constantDeclaration(
  ConstantContext context,
  ConstructorConstants owner,
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
  var scope = context.lexicalClass;
  var typeScope = context.typeScope;
  var parameters = context.initializerParameters;
  context.lexicalClass = owner.classId;
  context.typeScope = const <int>[];
  context.initializerParameters = const <ConstantValue>[];
  var value = ConstantValue(tNull, tNull, 0, '');
  if (expression != null)
    value = _evaluateConstant(context, expression, true, type, false);
  else if (!field && owner.syntax.parameters[index].superFormal) {
    final parent = context.constructors[owner.plan.superTarget]!;
    final associated = owner.plan.superParameters[index];
    final parameter = parent.syntax.parameters[associated];
    if (parameter.kind != astRequiredPositional && !parameter.required) {
      final inherited = _constantDeclaration(
        context,
        parent,
        associated,
        false,
        true,
      );
      if (typeIsSubtype(constantValueType(inherited), type))
        value = constantWithType(inherited, type);
    }
  }
  context.lexicalClass = scope;
  context.typeScope = typeScope;
  context.initializerParameters = parameters;
  value = _constantChecked(context, value, type, token, true);
  owner.values[slot] = value;
  owner.states[slot] = 3;
  return value;
}

ConstantValue constructorParameterDefault(
  ConstantContext context,
  int function,
  int parameter,
) => _constantDeclaration(
  context,
  context.constructors[function]!,
  parameter,
  false,
  true,
);

List<ConstantValue> _constantParameterFrame(
  ConstructorConstants owner,
  List<ConstantValue> values,
) {
  var count = 0;
  var p = 0;
  while (p < owner.syntax.parameters.length) {
    var binding = owner.syntax.parameters[p].binding;
    if (binding >= count) count = binding + 1;
    p++;
  }
  var frame = List<ConstantValue>.filled(
    count,
    ConstantValue(-1, tNull, 0, ''),
  );
  p = 0;
  while (p < owner.syntax.parameters.length) {
    var binding = owner.syntax.parameters[p].binding;
    if (binding >= 0) frame[binding] = values[p];
    p++;
  }
  return frame;
}

ConstantValue _constantInitializer(
  ConstantContext context,
  ConstructorConstants owner,
  ConstructorStep step,
  bool active,
) {
  var initializer = owner.syntax.initializers[step.index];
  var type = owner.fieldTypes[step.field];
  var value = _evaluateConstant(
    context,
    initializer.expression,
    active,
    type,
    false,
  );
  return _constantChecked(context, value, type, initializer.token, active);
}

ConstructorConstants _constantRedirectTarget(
  ConstantContext context,
  ConstructorConstants owner,
) {
  var function = owner.plan.redirectTarget;
  ConstructorConstants? target;
  if (function >= 0 && function < context.constructors.length)
    target = context.constructors[function];
  if (target == null || !target.syntax.constant)
    _constantError(
      context,
      owner.syntax.initializers[0].token,
      'const redirect requires a const target',
    );
  return target;
}

ConstructorConstants _constantSuperTarget(
  ConstantContext context,
  ConstructorConstants owner,
) {
  final function = owner.plan.superTarget;
  final target = function < context.constructors.length
      ? context.constructors[function]
      : null;
  if (target == null || !target.syntax.constant)
    _constantError(
      context,
      owner.syntax.token,
      'const constructor requires a const superclass constructor',
    );
  return target;
}

List<ConstantValue> _constantArguments(
  ConstantContext context,
  ConstructorConstants owner,
  AstExpression call,
  bool active,
  bool redirectArguments,
) {
  checkArgumentOrder(context.symbols.program, call);
  var bindings = bindArguments(context.symbols.program, owner.syntax, call, 1);
  var parameters = List<ConstantValue>.filled(
    owner.parameterTypes.length,
    ConstantValue(-1, tNull, 0, ''),
  );
  var allow = context.allowInitializerParameters;
  context.allowInitializerParameters = redirectArguments;
  var i = 1;
  while (i < call.children.length) {
    var argument = call.children[i];
    if (argument.kind == astNamedArgument) argument = argument.children[0];
    var parameter = bindings[i - 1];
    var type = owner.parameterTypes[parameter];
    var value = _evaluateConstant(
      context,
      argument,
      active,
      type,
      !redirectArguments,
    );
    parameters[parameter] = _constantChecked(
      context,
      value,
      type,
      argument.token,
      active,
    );
    i++;
  }
  context.allowInitializerParameters = allow;
  i = 0;
  while (i < parameters.length) {
    if (parameters[i].type < 0)
      parameters[i] = _constantDeclaration(context, owner, i, false, active);
    i++;
  }
  return parameters;
}

void checkConstantConstructors(ConstantContext context) {
  var c = 0;
  while (c < context.constructors.length) {
    var owner = context.constructors[c];
    if (owner != null && owner.syntax.constant) {
      ConstructorConstants? target;
      if (owner.plan.redirectTarget >= 0)
        target = _constantRedirectTarget(context, owner);
      final parent = owner.plan.superTarget >= 0
          ? _constantSuperTarget(context, owner)
          : null;
      var p = 0;
      while (p < owner.syntax.parameters.length) {
        var parameter = owner.syntax.parameters[p];
        if (parameter.kind != astRequiredPositional && !parameter.required)
          _constantDeclaration(context, owner, p, false, true);
        p++;
      }
      if (target == null) {
        var f = 0;
        while (f < owner.owner.fields.length) {
          if (owner.owner.fields[f].initializer.isNotEmpty)
            _constantDeclaration(context, owner, f, true, true);
          f++;
        }
      }
      if (owner.syntax.initializers.isNotEmpty || parent != null) {
        var parameters = <ConstantValue>[];
        p = 0;
        while (p < owner.parameterTypes.length) {
          parameters.add(ConstantValue(owner.parameterTypes[p], tNull, 0, ''));
          p++;
        }
        var scope = context.lexicalClass;
        var previous = context.initializerParameters;
        var allow = context.allowInitializerParameters;
        context.lexicalClass = owner.classId;
        context.initializerParameters = _constantParameterFrame(
          owner,
          parameters,
        );
        context.allowInitializerParameters = true;
        if (target != null) {
          _constantArguments(
            context,
            target,
            owner.syntax.initializers[0].expression,
            false,
            true,
          );
        } else {
          var i = 0;
          while (i < owner.plan.steps.length) {
            var step = owner.plan.steps[i];
            if (step.kind == constructorExplicit)
              _constantInitializer(context, owner, step, false);
            i++;
          }
          if (parent != null)
            _constantArguments(
              context,
              parent,
              owner.plan.superCall!,
              false,
              true,
            );
        }
        context.lexicalClass = scope;
        context.initializerParameters = previous;
        context.allowInitializerParameters = allow;
      }
    }
    c++;
  }
}

ConstantValue _constantInvoke(
  ConstantContext context,
  ConstructorConstants owner,
  List<ConstantValue> parameters,
  bool active,
) {
  if (!active) {
    // Arguments are checked by the caller; declaration qualification checks the
    // initializer once, without evaluating a nested constructor body.
    var type = classType(owner.classId);
    return ConstantValue(type, type, -1, '');
  }
  var scope = context.lexicalClass;
  var typeScope = context.typeScope;
  var previous = context.initializerParameters;
  var allow = context.allowInitializerParameters;
  var depth = context.invocations.length;
  context.typeScope = const <int>[];
  while (true) {
    var call = 0;
    while (call < context.invocations.length) {
      var previousCall = context.invocations[call];
      if (previousCall.owner == owner) {
        var parameter = 0;
        while (parameter < parameters.length &&
            _constantSame(
              previousCall.parameters[parameter],
              parameters[parameter],
            )) {
          parameter++;
        }
        if (parameter == parameters.length)
          _constantError(
            context,
            owner.syntax.token,
            'cyclic constant constructor invocation',
          );
      }
      call++;
    }
    context.invocations.add(_ConstantInvocation(owner, parameters));
    context.lexicalClass = owner.classId;
    if (owner.syntax.initializers.isNotEmpty || owner.plan.superCall != null)
      context.initializerParameters = _constantParameterFrame(
        owner,
        parameters,
      );
    else
      context.initializerParameters = const <ConstantValue>[];
    context.allowInitializerParameters = true;
    if (owner.plan.redirectTarget < 0) break;
    var target = _constantRedirectTarget(context, owner);
    parameters = _constantArguments(
      context,
      target,
      owner.syntax.initializers[0].expression,
      active,
      true,
    );
    owner = target;
  }
  var fields = <ConstantValue>[];
  var i = 0;
  while (i < owner.fieldTypes.length) {
    fields.add(_constantDeclaration(context, owner, i, true, false));
    i++;
  }
  i = 0;
  while (i < owner.plan.steps.length) {
    var step = owner.plan.steps[i];
    if (step.kind == constructorDeclaration) {
      fields[step.field] = _constantDeclaration(
        context,
        owner,
        step.index,
        true,
        active,
      );
    } else if (step.kind == constructorFormal) {
      fields[step.field] = _constantChecked(
        context,
        parameters[step.index],
        owner.fieldTypes[step.field],
        owner.syntax.parameters[step.index].token,
        active,
      );
    } else {
      // Potential qualification was checked once at the declaration.
      fields[step.field] = _constantInitializer(context, owner, step, true);
    }
    i++;
  }
  if (owner.plan.superTarget >= 0) {
    final parent = _constantSuperTarget(context, owner);
    final arguments = _constantArguments(
      context,
      parent,
      owner.plan.superCall!,
      true,
      true,
    );
    final inherited = _constantInvoke(context, parent, arguments, true);
    fields = <ConstantValue>[...inherited.elements, ...fields];
  }
  context.lexicalClass = scope;
  context.typeScope = typeScope;
  context.initializerParameters = previous;
  context.allowInitializerParameters = allow;
  while (context.invocations.length > depth) context.invocations.removeLast();
  var type = classType(owner.classId);
  var value = ConstantValue(type, type, -1, '');
  value.elements = fields;
  return _constantAggregate(context, value);
}

ConstantValue _constantConstructor(
  ConstantContext context,
  AstExpression expression,
  bool active,
  bool implicitConst,
) {
  if (expression.text == astCallNew)
    _constantError(
      context,
      expression.token,
      'new expression is not a constant expression',
    );
  if (expression.text == astCallValue)
    _constantError(
      context,
      expression.token,
      'constant expression requires a direct constructor invocation',
    );
  var callee = expression.children[0];
  var classExpression = callee;
  var symbol = _constantSymbol(context, callee);
  var arguments = expression.typeArguments;
  if ((callee.kind == astName || callee.kind == astMember) &&
      callee.typeArguments.isNotEmpty) {
    if (arguments.isNotEmpty)
      _constantError(
        context,
        callee.token,
        'duplicate constructor type arguments',
      );
    arguments = callee.typeArguments;
  }
  var classType = _constantConstructorType(
    context,
    symbol,
    arguments,
    callee.token,
  );
  var classId = classType < 0 ? -1 : resolvedTypeClassOwner(classType);
  var name = '';
  if (classId < 0 && callee.kind == astMember) {
    classExpression = callee.children[0];
    symbol = _constantSymbol(context, classExpression);
    classType = _constantConstructorType(
      context,
      symbol,
      classExpression.typeArguments,
      classExpression.token,
    );
    classId = classType < 0 ? -1 : resolvedTypeClassOwner(classType);
    if (classId >= 0 && expression.typeArguments.isNotEmpty)
      _constantError(
        context,
        expression.token,
        'constructor selector does not accept type arguments',
      );
    if (classId >= 0)
      name = constructorSelector(
        context.symbols.program,
        callee.text,
        callee.token,
      );
  }
  if (classId < 0)
    _constantError(
      context,
      expression.token,
      'constant expression requires a const constructor',
    );
  var constructor = lookupConstructor(context.classMembers[classId], name);
  if (constructor < 0)
    _constantError(context, callee.token, 'unknown constructor');
  var function = context.classConstructors[classId][constructor];
  ConstructorConstants? owner;
  if (function < context.constructors.length)
    owner = context.constructors[function];
  if (owner == null ||
      !owner.syntax.constant ||
      !expression.constant && !implicitConst)
    _constantError(
      context,
      expression.token,
      'constant constructor requires const',
    );
  if (owner.owner.isAbstract)
    _constantError(
      context,
      expression.token,
      'cannot instantiate an abstract class',
    );
  var source = context.symbols.program;
  if (name.startsWith('_') &&
      sourceLibrary(source, source.tokens[callee.token].source) !=
          sourceLibrary(source, source.tokens[owner.owner.token].source))
    _constantError(
      context,
      callee.token,
      'private constructor is not accessible',
    );
  var parameters = _constantArguments(
    context,
    owner,
    expression,
    active,
    false,
  );
  return _constantInvoke(context, owner, parameters, active);
}

ConstantValue _evaluateConstant(
  ConstantContext context,
  AstExpression expression,
  bool active,
  int expected,
  bool implicitConst,
) {
  var kind = expression.kind;
  if (kind == astImplicitReceiver) return context.implicitReceiver!;
  if (kind == astNullAware) {
    var source = expression.children[0];
    var body = expression.children[1];
    var symbol = _constantSymbol(context, source);
    if (symbol >= 0 &&
        (declarationClassOwner(context.symbols, symbol) >= 0 ||
            context.symbols.declarations[symbol].kind == symbolType)) {
      var access = astImplicitReceiverAccess(body);
      var receiver = access.children[0];
      access.children[0] = source;
      var value = _evaluateConstant(
        context,
        body,
        active,
        expected,
        implicitConst,
      );
      access.children[0] = receiver;
      return value;
    }
    var receiver = _evaluateConstant(
      context,
      source,
      active,
      -1,
      implicitConst,
    );
    if (receiver.type == tVoid)
      _constantError(
        context,
        source.token,
        'void cannot be a null-aware receiver',
      );
    var previous = context.implicitReceiver;
    context.implicitReceiver = constantWithType(
      receiver,
      typingNullAssertion(receiver.type),
    );
    var taken = active && receiver.kind != tNull;
    var value = _evaluateConstant(
      context,
      body,
      taken,
      expected,
      implicitConst,
    );
    context.implicitReceiver = previous;
    var type = value.type == tVoid ? tVoid : nullableType(value.type);
    if (!taken) return ConstantValue(type, tNull, 0, '');
    return constantWithType(value, type);
  }
  if (kind == astDouble)
    return ConstantValue(
      tDouble,
      tDouble,
      decodeDoubleLiteral(context.symbols.program, expression),
      '',
    );
  if (doubleContext(expected) &&
      (kind == astInteger || isNegatedIntegerLiteral(expression)))
    return ConstantValue(
      tDouble,
      tDouble,
      decodeIntegerAsDouble(context.symbols.program, expression),
      '',
    );
  if (kind == astInteger) {
    return ConstantValue(
      tInt,
      tInt,
      decodeIntegerLiteral(context.symbols.program, expression),
      '',
    );
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
      if (binding < context.initializerParameters.length &&
          context.initializerParameters[binding].type >= 0) {
        if (!context.allowInitializerParameters)
          _constantError(
            context,
            expression.token,
            'constructor parameter is not a constant expression',
          );
        return context.initializerParameters[binding];
      }
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
    var owner = _constantStaticOwner(context, expression);
    if (owner >= 0)
      return _constantStaticReference(
        context,
        expression,
        owner,
        active,
        false,
      );
    return _constantReference(
      context,
      expression,
      _constantSymbol(context, expression),
      active,
    );
  }
  if (kind == astMember) {
    final receiverSymbol = _constantSymbol(context, expression.children[0]);
    if (receiverSymbol >= 0) {
      final declaration = context.symbols.declarations[receiverSymbol];
      if (declaration.source == sourceCore &&
          declaration.kind == symbolType &&
          declaration.target == tDouble) {
        final value = binary64Constant(expression.text);
        if (value != null) return ConstantValue(tDouble, tDouble, value, '');
      }
    }
    var owner = _constantStaticOwner(context, expression);
    if (owner >= 0)
      return _constantStaticReference(
        context,
        expression,
        owner,
        active,
        false,
      );
    var receiver = expression.children[0];
    var symbol = _constantSymbol(context, expression);
    if (symbol != -1) {
      return _constantReference(context, expression, symbol, active);
    }
    var value = _evaluateConstant(context, receiver, active, -1, implicitConst);
    if (value.type == tNever) return ConstantValue(tNever, tNull, 0, '');
    if (expression.text == 'length') {
      if (value.type == tString || value.type == tDynamic) {
        var type = tInt;
        if (value.type == tDynamic) type = tDynamic;
        if (!active) return ConstantValue(type, tNull, 0, '');
        if (value.kind == tString) {
          return ConstantValue(type, tInt, value.text.length, '');
        }
      }
      if (!active && typeIsList(value.type))
        return ConstantValue(tInt, tNull, 0, '');
    }
    return _constantError(
      context,
      expression.token,
      'unsupported constant property',
    );
  }
  if (kind == astIndex) {
    var receiver = _evaluateConstant(
      context,
      expression.children[0],
      active,
      -1,
      implicitConst,
    );
    var index = _evaluateConstant(
      context,
      expression.children[1],
      active,
      -1,
      implicitConst,
    );
    var type = receiver.type;
    if (index.type == tVoid ||
        type != tNever &&
            type != tDynamic &&
            !typingAssignable(index.type, tInt))
      _constantError(context, expression.token, 'invalid constant index type');
    if (typeIsList(type))
      type = typeArgument(type);
    else if (type != tNever && type != tString && type != tDynamic)
      _constantError(
        context,
        expression.token,
        'invalid constant index receiver',
      );
    if (active)
      _constantError(
        context,
        expression.token,
        'indexing is not a constant operation',
      );
    return ConstantValue(type, tNull, 0, '');
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
    if (isNegatedIntegerLiteral(expression)) {
      return ConstantValue(
        tInt,
        tInt,
        decodeIntegerLiteral(context.symbols.program, expression),
        '',
      );
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
    if (expression.text == '-')
      integer = value.kind == tDouble ? integer ^ binary64Sign : -integer;
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
    return _constantBinary(
      context,
      expression,
      active,
      implicitConst,
      expected,
    );
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
