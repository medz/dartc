import 'ast.dart';
import 'parser.dart';
import 'ir.dart';
import 'types.dart';
import 'scanner.dart';
import 'source.dart';
import 'symbols.dart';

class GlobalInitializer {
  List<int> code;
  List<int> types;
  List<int> locals;
  int result;
  int getter;
  int setter;
  int state;

  GlobalInitializer(
    this.code,
    this.types,
    this.locals,
    this.result,
    this.getter,
    this.setter,
    this.state,
  );
}

SourceProgram feSources = SourceProgram(
  <SourceFile>[],
  <int>[],
  <Token>[],
  -1,
  0,
  '',
  -1,
);
List<Token> feTokens = <Token>[];
int feAt = 0;
SymbolTable feSymbols = SymbolTable(feSources, <DeclarationSymbol>[]);
List<AstFunction> feFunctionNodes = <AstFunction>[];
List<AstClass> feClassNodes = <AstClass>[];
List<AstVariable> feGlobalNodes = <AstVariable>[];
List<AstVariable> feFieldNodes = <AstVariable>[];
List<int> feClassSources = <int>[];
List<int> feGlobalSources = <int>[];
List<int> feRawGlobals = <int>[];
List<GlobalInitializer> feGlobalInitializers = <GlobalInitializer>[];
int feRuntimeTokens = 0;
int fePendingTypeClosers = 0;
List<int> _feLiteralTypes = <int>[];
List<int> _feLiteralValues = <int>[];
List<int> feParamStarts = <int>[];
List<String> feParamNames = <String>[];
List<int> feParamTypes = <int>[];
List<String> feLocalNames = <String>[];
List<int> feLocalTypes = <int>[];
List<int> feLocalSlots = <int>[];
List<int> feBreaks = <int>[];
List<int> feContinues = <int>[];
List<int> feLoopBreaks = <int>[];
List<int> feLoopContinues = <int>[];
int feNextLocal = 0;
int feFunction = 0;
List<int> feSlotTypes = <int>[];
List<String> feNativeNames = <String>[];
List<int> feNativeParams = <int>[];
int feInitializingGlobal = -1;
List<String> feClassNames = <String>[];
List<int> feClassFieldCounts = <int>[];
List<int> feClassConstructors = <int>[];
List<String> feFieldNames = <String>[];
List<int> feFieldTypes = <int>[];
List<int> feFieldClasses = <int>[];
List<int> feFieldIndices = <int>[];
List<int> feOwners = <int>[];
List<int> feConstructors = <int>[];
List<int> feParamFields = <int>[];

void feError(String message) {
  sourceError(feSources, feTokens[feAt], message);
}

String fePeek() {
  return feTokens[feAt].text;
}

bool feIs(String text) {
  return feTokens[feAt].kind != tokenString && fePeek() == text;
}

bool feTake(String text) {
  if (feIs(text)) {
    feAt++;
    return true;
  }
  return false;
}

void feExpect(String text) {
  if (!feTake(text)) feError('expected ' + text);
}

String feName() {
  if (feTokens[feAt].kind != tokenIdentifier) feError('expected name');
  var name = fePeek();
  feAt++;
  return name;
}

int feClassId(String name) {
  for (var i = 0; i < feClassNames.length; i++) {
    if (feClassNames[i] == name) return i;
  }
  return -1;
}

bool feClassType(int type) {
  return typeIsClass(type);
}

int feField(int owner, String name) {
  for (var i = 0; i < feFieldNames.length; i++) {
    if (feFieldClasses[i] == owner && feFieldNames[i] == name) return i;
  }
  feError('unknown field ' + feClassNames[owner] + '.' + name);
  return 0;
}

int feMethod(int owner, String name, bool getter) {
  var i = 1;
  while (i < feFunctionNodes.length) {
    if (feOwners[i] == owner &&
        feFunctionNodes[i].name == name &&
        feFunctionNodes[i].getter == getter)
      return i;
    i++;
  }
  return -1;
}

void feDeclare(int source, String name, int kind, int target, int token) {
  if (declareSymbol(feSymbols, source, name, kind, target) < 0) {
    feAstError(token, 'duplicate declaration ' + name);
  }
}

int feRegisterFunction(AstFunction syntax, int owner, bool constructor) {
  if (syntax.external) return -1;
  var id = functions.length;
  var start = feParamNames.length;
  var count = 0;
  var source = feTokens[syntax.token].source;
  var name = syntax.name;
  var result = tInt;
  if (constructor)
    result = classType(owner);
  else if (syntax.result.name != '')
    result = feLowerType(syntax.result);
  if (owner >= 0) {
    name = feClassNames[owner] + '.' + syntax.name;
    feParamNames.add('this');
    feParamTypes.add(classType(owner));
    feParamFields.add(-1);
    count++;
  }
  var p = 0;
  while (p < syntax.parameters.length) {
    var parameter = syntax.parameters[p];
    var type = tInt;
    var field = -1;
    if (parameter.fieldFormal) {
      var entry = feField(owner, parameter.name);
      type = feFieldTypes[entry];
      field = feFieldIndices[entry];
    } else if (parameter.type.name != '') {
      type = feLowerType(parameter.type);
    }
    feParamNames.add(parameter.name);
    feParamTypes.add(type);
    feParamFields.add(field);
    count++;
    p++;
  }
  var types = <int>[];
  p = 0;
  while (p < count) {
    types.add(feParamTypes[start + p]);
    p++;
  }
  functions.add(
    FunctionInfo(name, 0, count, count, result, types, <int>[], source),
  );
  feParamStarts.add(start);
  feFunctionNodes.add(syntax);
  feOwners.add(owner);
  if (constructor) {
    feConstructors.add(1);
    feClassConstructors[owner] = id;
  } else {
    feConstructors.add(0);
  }
  if (owner < 0)
    feDeclare(source, syntax.name, symbolFunction, id, syntax.token);
  return id;
}

void feRecordLiteral(int global, AstVariable syntax) {
  if (syntax.modifier != 'const' || syntax.initializer.length == 0) return;
  var expression = syntax.initializer[0];
  var sign = 1;
  if (expression.kind == astUnary && expression.text == '-') {
    sign = -1;
    expression = expression.children[0];
  }
  var type = 0;
  var value = 0;
  if (expression.kind == astInteger) {
    type = tInt;
    value = int.parse(expression.text) * sign;
  } else if (sign == 1 && expression.kind == astBoolean) {
    type = tBool;
    if (expression.text == 'true') value = 1;
  }
  if (type == 0) return;
  if (globalTypes[global] != 0 && globalTypes[global] != type) return;
  _feLiteralTypes[global] = type;
  _feLiteralValues[global] = value;
  globalTypes[global] = type;
}

void feCollectDeclarations(AstUnit unit) {
  var i = 0;
  while (i < unit.classes.length) {
    var syntax = unit.classes[i];
    var source = feTokens[syntax.token].source;
    var owner = feClassNames.length;
    classType(owner);
    feClassNames.add(syntax.name);
    feClassSources.add(source);
    feClassNodes.add(syntax);
    feClassFieldCounts.add(0);
    feClassConstructors.add(-1);
    classSizes.add(16);
    classPointerMasks.add(0);
    feDeclare(source, syntax.name, symbolClass, owner, syntax.token);
    if (source == feSources.core && !syntax.name.startsWith('_')) {
      feDeclare(sourceCore, syntax.name, symbolClass, owner, syntax.token);
    }
    i++;
  }
  i = 0;
  while (i < unit.classes.length) {
    var fields = unit.classes[i].fields;
    var field = 0;
    while (field < fields.length) {
      var syntax = fields[field];
      if (syntax.type.name == '')
        feAstError(syntax.token, 'field requires a type');
      var type = feLowerType(syntax.type);
      feFieldNames.add(syntax.name);
      feFieldNodes.add(syntax);
      feFieldTypes.add(type);
      feFieldClasses.add(i);
      feFieldIndices.add(field);
      if (typeIsReference(type)) {
        classPointerMasks[i] = classPointerMasks[i] | (1 << field);
      }
      field++;
    }
    feClassFieldCounts[i] = field;
    classSizes[i] = 16 + field * 8;
    i++;
  }
  i = 0;
  while (i < unit.variables.length) {
    var syntax = unit.variables[i];
    var source = feTokens[syntax.token].source;
    var type = 0;
    if (syntax.type.name != '') type = feLowerType(syntax.type);
    var global = globalNames.length;
    globalNames.add(syntax.name);
    globalTypes.add(type);
    feGlobalSources.add(source);
    feGlobalNodes.add(syntax);
    if (feRuntimeTokens > 0 && source == 0)
      feRawGlobals.add(1);
    else
      feRawGlobals.add(0);
    _feLiteralTypes.add(0);
    _feLiteralValues.add(0);
    feRecordLiteral(global, syntax);
    feDeclare(source, syntax.name, symbolGlobal, global, syntax.token);
    i++;
  }
  i = 0;
  while (i < unit.typedefs.length) {
    var syntax = unit.typedefs[i];
    if (syntax.result.name != 'Int64') {
      feAstError(syntax.token, 'FFI callbacks currently require Int64');
    }
    var p = 0;
    while (p < syntax.parameterTypes.length) {
      if (syntax.parameterTypes[p].name != 'Int64') {
        feAstError(syntax.token, 'FFI callbacks currently require Int64');
      }
      p++;
    }
    if (p > 8)
      feAstError(
        syntax.token,
        'FFI callbacks support up to eight Int64 parameters',
      );
    var target = feNativeNames.length;
    feNativeNames.add(syntax.name);
    feNativeParams.add(p);
    feDeclare(
      feTokens[syntax.token].source,
      syntax.name,
      symbolNativeType,
      target,
      syntax.token,
    );
    i++;
  }
  i = 0;
  while (i < unit.functions.length) {
    feRegisterFunction(unit.functions[i], -1, false);
    i++;
  }
  i = 0;
  while (i < unit.classes.length) {
    var syntax = unit.classes[i];
    var constructor = 0;
    while (constructor < syntax.constructors.length) {
      feRegisterFunction(syntax.constructors[constructor], i, true);
      constructor++;
    }
    if (constructor == 0) {
      feRegisterFunction(
        AstFunction(
          syntax.name,
          AstType(syntax.name, <AstType>[], syntax.token),
          <AstParameter>[],
          <AstStatement>[],
          <AstExpression>[],
          false,
          syntax.token,
          false,
        ),
        i,
        true,
      );
    }
    var method = 0;
    while (method < syntax.methods.length) {
      feRegisterFunction(syntax.methods[method], i, false);
      method++;
    }
    i++;
  }
}

void feEmit(int op) {
  var type = tVoid;
  if (op >= opAdd && op <= opBitNot) type = tInt;
  if (op >= opEq && op <= opGe || op == opNot) type = tBool;
  ir.add(op);
  irTypes.add(type);
}

void feWord(int value) {
  ir.add(value);
  irTypes.add(tVoid);
}

void feOperand(int op, int value) {
  var position = ir.length;
  feEmit(op);
  feWord(value);
  if (op == opInt) irTypes[position] = tInt;
  if (op == opString) irTypes[position] = tString;
  if (op == opDescriptor) irTypes[position] = tPointer;
  if (op == opLoadLocal) irTypes[position] = feSlotTypes[value];
  if (op == opLoadGlobal) irTypes[position] = globalTypes[value];
}

void feInteger(int value, int type) {
  feOperand(opInt, value);
  irTypes[ir.length - 2] = type;
}

void feDuplicate(int type) {
  feEmit(opDup);
  irTypes[ir.length - 1] = type;
}

int feBuiltinType(int id) {
  if (id == bIntToString ||
      id == bStringConcat ||
      id == bStringSubstring ||
      id == bStringFromCodes ||
      id == bHostRead ||
      id == bHostStdPath)
    return tString;
  if (id == bStringEqual || id == bStringStartsWith || id == bStringEndsWith)
    return tBool;
  if (id == bStringLength ||
      id == bStringCodeUnit ||
      id == bStringIndexOf ||
      id == bStringLastIndexOf ||
      id == bIntParse ||
      id == bListLength ||
      id == bHostTarget ||
      id == bNativeLoad64 ||
      id == bNativeLoad8 ||
      id == bNativeLoad16 ||
      id == bNativeStore16 ||
      id == bNativeSyscall ||
      id == bNativeTarget)
    return tInt;
  if (id == bArguments) return listType(tString);
  return tVoid;
}

void feBuiltinTyped(int id, int count, int type) {
  feEmit(opBuiltin);
  irTypes[ir.length - 1] = type;
  feWord(id);
  feWord(count);
}

void feBuiltin(int id, int count) {
  feBuiltinTyped(id, count, feBuiltinType(id));
}

void feCall(int function, int count) {
  feEmit(opCall);
  irTypes[ir.length - 1] = functions[function].result;
  feWord(function);
  feWord(count);
}

int feJump(int op) {
  feOperand(op, 0);
  return ir.length - 1;
}

void fePatch(int position, int target) {
  ir[position] = target;
}

int feString(String text) {
  for (var i = 0; i < strings.length; i++) {
    if (strings[i] == text) return i;
  }
  strings.add(text);
  return strings.length - 1;
}

int feLocal(String name) {
  for (var i = feLocalNames.length - 1; i >= 0; i--) {
    if (feLocalNames[i] == name) return i;
  }
  return -1;
}

int feGlobal(String name) {
  for (var i = 0; i < globalNames.length; i++) {
    if (globalNames[i] == name) return i;
  }
  return -1;
}

int feFindFunction(String name) {
  for (var i = 1; i < functions.length; i++) {
    if (functions[i].name == name) return i;
  }
  return -1;
}

int feVariableType(String name) {
  var local = feLocal(name);
  if (local >= 0) return feLocalTypes[local];
  var global = feGlobal(name);
  if (global >= 0) {
    if (globalTypes[global] == 0 &&
        imageKind == 0 &&
        feRawGlobals[global] == 0) {
      feInferGlobal(global);
    }
    return globalTypes[global];
  }
  feError('unknown variable ' + name);
  return tInt;
}

void feLoad(String name) {
  var local = feLocal(name);
  if (local >= 0) {
    feOperand(opLoadLocal, feLocalSlots[local]);
    return;
  }
  var global = feGlobal(name);
  if (global >= 0) {
    if (_feLiteralTypes[global] != 0) {
      feInteger(_feLiteralValues[global], _feLiteralTypes[global]);
    } else if (imageKind == 0 && feRawGlobals[global] == 0) {
      if (globalTypes[global] == 0) feInferGlobal(global);
      feCall(feGlobalInitializers[global].getter, 0);
    } else {
      feOperand(opLoadGlobal, global);
    }
    return;
  }
  feError('unknown variable ' + name);
}

void feStore(String name) {
  var local = feLocal(name);
  if (local >= 0) {
    feOperand(opStoreLocal, feLocalSlots[local]);
    return;
  }
  var global = feGlobal(name);
  if (global >= 0) {
    if (imageKind == 0 &&
        feRawGlobals[global] == 0 &&
        _feLiteralTypes[global] == 0) {
      feCall(feGlobalInitializers[global].setter, 1);
      feEmit(opPop);
    } else {
      feOperand(opStoreGlobal, global);
    }
    return;
  }
  feError('unknown variable ' + name);
}

int feTemp(int type) {
  var slot = feNextLocal;
  feNextLocal++;
  feSlotTypes.add(type);
  return slot;
}

void feScopeEnd(int start) {
  while (feLocalNames.length > start) {
    feLocalNames.removeLast();
    feLocalTypes.removeLast();
    feLocalSlots.removeLast();
  }
}

class FeLvalue {
  String name;
  int type;
  int container;
  int receiver;
  int index;

  FeLvalue(this.name, this.type, this.container, this.receiver, this.index);
}

void feAstError(int token, String message) {
  sourceError(feSources, feTokens[token], message);
}

int feBinaryOp(String op) {
  if (op == '+') return opAdd;
  if (op == '-') return opSub;
  if (op == '*') return opMul;
  if (op == '~/') return opDiv;
  if (op == '%') return opMod;
  if (op == '&') return opAnd;
  if (op == '|') return opOr;
  if (op == '^') return opXor;
  if (op == '<<') return opShl;
  if (op == '>>') return opShr;
  if (op == '>>>') return opUshr;
  if (op == '==') return opEq;
  if (op == '!=') return opNe;
  if (op == '<') return opLt;
  if (op == '<=') return opLe;
  if (op == '>') return opGt;
  if (op == '>=') return opGe;
  feError('unsupported operator ' + op);
  return opAdd;
}

int feCombine(String op, int left, int right) {
  if (op == '+' && left == tString && right == tString) {
    feBuiltin(bStringConcat, 2);
    return tString;
  }
  if ((op == '==' || op == '!=') && left == tString && right == tString) {
    feBuiltin(bStringEqual, 2);
    if (op == '!=') feEmit(opNot);
    return tBool;
  }
  feEmit(feBinaryOp(op));
  if (op == '==' ||
      op == '!=' ||
      op == '<' ||
      op == '<=' ||
      op == '>' ||
      op == '>=')
    return tBool;
  return tInt;
}

int feLowerType(AstType syntax) {
  var name = syntax.name;
  if (name == 'int' || name == 'dynamic') return tInt;
  if (name == 'String') return tString;
  if (name == 'bool') return tBool;
  if (name == 'void') return tVoid;
  if (name == 'List') {
    var element = tInt;
    if (syntax.arguments.length != 0)
      element = feLowerType(syntax.arguments[0]);
    return listType(element);
  }
  var owner = feClassId(name);
  if (owner >= 0) return classType(owner);
  feAstError(syntax.token, 'unsupported type ' + name);
  return tInt;
}

int feLowerArguments(AstExpression call, int start) {
  var argument = start;
  while (argument < call.children.length) {
    var expression = call.children[argument];
    if (expression.kind == astNamedArgument) {
      feAstError(
        expression.token,
        'unsupported named argument ' + expression.text,
      );
    }
    feLowerExpression(expression);
    argument++;
  }
  return call.children.length - start;
}

int feLowerList(AstExpression expression) {
  var element = 0;
  if (expression.typeArguments.length != 0) {
    element = feLowerType(expression.typeArguments[0]);
  }
  var allocation = ir.length;
  var duplicates = <int>[];
  feBuiltinTyped(bListNew, 0, listType(element));
  var item = 0;
  while (item < expression.children.length) {
    duplicates.add(ir.length);
    feDuplicate(listType(element));
    var type = feLowerExpression(expression.children[item]);
    if (element == 0) element = type;
    feBuiltin(bListAdd, 2);
    feEmit(opPop);
    item++;
  }
  if (element == 0) element = tInt;
  var type = listType(element);
  irTypes[allocation] = type;
  for (var i = 0; i < duplicates.length; i++) irTypes[duplicates[i]] = type;
  return type;
}

int feLowerPointerBinding(AstExpression call) {
  if (imageKind == 0 || feInitializingGlobal < 0) {
    feAstError(
      call.token,
      'FFI callback bindings require library output and a top-level binding',
    );
  }
  var callee = call.children[0];
  if (callee.typeArguments.length != 1 || call.children.length < 2) {
    feAstError(call.token, 'FFI callback requires a signature and function');
  }
  var signature = callee.typeArguments[0].name;
  var native = -1;
  for (var i = 0; i < feNativeNames.length; i++) {
    if (feNativeNames[i] == signature) native = i;
  }
  if (native < 0) feAstError(call.token, 'unknown FFI signature ' + signature);
  var implementation = call.children[1];
  if (implementation.kind != astName) {
    feAstError(
      implementation.token,
      'FFI callback requires a function declaration',
    );
  }
  var function = feFindFunction(implementation.text);
  if (function < 0) {
    feAstError(
      implementation.token,
      'unknown callback function ' + implementation.text,
    );
  }
  if (functions[function].parameters != feNativeParams[native]) {
    feAstError(
      call.token,
      'FFI parameter count does not match ' + implementation.text,
    );
  }
  if (call.children.length > 2) {
    feLowerExpression(call.children[2]);
    feEmit(opPop);
  }
  exportNames.add(globalNames[feInitializingGlobal]);
  exportFunctions.add(function);
  exportParameters.add(feNativeParams[native]);
  feInteger(0, tPointer);
  return tPointer;
}

int feLowerBuiltinCall(AstExpression call) {
  var name = call.children[0].text;
  if (name == 'print') {
    if (call.children.length != 2)
      feAstError(call.token, 'argument count for print');
    var type = feLowerExpression(call.children[1]);
    if (type == tString)
      feBuiltin(bPrintString, 1);
    else if (type == tBool)
      feBuiltin(bPrintBool, 1);
    else
      feBuiltin(bPrintInt, 1);
    return tVoid;
  }
  var builtin = 0;
  var result = tInt;
  if (name == 'hostRead') {
    builtin = bHostRead;
    result = tString;
  }
  if (name == 'hostWrite') {
    builtin = bHostWrite;
    result = tVoid;
  }
  if (name == 'hostFinish') {
    builtin = bHostFinish;
    result = tVoid;
  }
  if (name == 'hostExit') {
    builtin = bHostExit;
    result = tVoid;
  }
  if (name == 'hostStdPath') {
    builtin = bHostStdPath;
    result = tString;
  }
  if (name == 'hostTarget') builtin = bHostTarget;
  if (name == 'nativeLoad64') builtin = bNativeLoad64;
  if (name == 'nativeLoad8') builtin = bNativeLoad8;
  if (name == 'nativeLoad16') builtin = bNativeLoad16;
  if (name == 'nativeStore64') {
    builtin = bNativeStore64;
    result = tVoid;
  }
  if (name == 'nativeStore8') {
    builtin = bNativeStore8;
    result = tVoid;
  }
  if (name == 'nativeStore16') builtin = bNativeStore16;
  if (name == 'nativeSyscall') builtin = bNativeSyscall;
  if (name == 'nativeTarget') builtin = bNativeTarget;
  if (builtin == 0) feAstError(call.token, 'unknown function ' + name);
  var count = feLowerArguments(call, 1);
  feBuiltin(builtin, count);
  return result;
}

int feLowerStaticCall(AstExpression call) {
  var callee = call.children[0];
  var receiver = callee.children[0];
  var name = receiver.text;
  var member = callee.text;
  if (name == 'Pointer' && member == 'fromFunction') {
    return feLowerPointerBinding(call);
  }
  if (name == 'List' && member == 'filled') {
    if (call.children.length < 3) {
      feAstError(call.token, 'List.filled requires length and value');
    }
    var element = tInt;
    if (receiver.typeArguments.length != 0) {
      element = feLowerType(receiver.typeArguments[0]);
    }
    feLowerExpression(call.children[1]);
    var valueType = feLowerExpression(call.children[2]);
    var argument = 3;
    while (argument < call.children.length) {
      var named = call.children[argument];
      if (named.kind != astNamedArgument || named.text != 'growable') {
        feAstError(named.token, 'unsupported List.filled argument');
      }
      feLowerExpression(named.children[0]);
      feEmit(opPop);
      argument++;
    }
    if (element == tInt && valueType != tInt) element = valueType;
    var type = listType(element);
    feBuiltinTyped(bListFilled, 2, type);
    return type;
  }
  if (name == 'String' && member == 'fromCharCodes') {
    var count = feLowerArguments(call, 1);
    feBuiltin(bStringFromCodes, count);
    return tString;
  }
  if (name == 'int' && member == 'parse') {
    var count = feLowerArguments(call, 1);
    feBuiltin(bIntParse, count);
    return tInt;
  }
  feAstError(call.token, 'unsupported static call ' + name + '.' + member);
  return tInt;
}

int feLowerMemberCall(AstExpression call) {
  var callee = call.children[0];
  var receiver = callee.children[0];
  var member = callee.text;
  var type = feLowerExpression(receiver);
  if (feClassType(type)) {
    var owner = typeArgument(type);
    var function = feMethod(owner, member, false);
    if (function < 0) feAstError(call.token, 'unknown method ' + member);
    var count = feLowerArguments(call, 1) + 1;
    if (functions[function].parameters != count) {
      feAstError(call.token, 'method argument count for ' + member);
    }
    feCall(function, count);
    return functions[function].result;
  }
  if (member == 'toString') {
    if (call.children.length != 1)
      feAstError(call.token, 'argument count for toString');
    if (type != tString) feBuiltin(bIntToString, 1);
    return tString;
  }
  var count = feLowerArguments(call, 1);
  if (typeIsList(type)) {
    if (member == 'add') {
      feBuiltin(bListAdd, count + 1);
      return tVoid;
    }
    if (member == 'removeLast') {
      var element = typeArgument(type);
      feBuiltinTyped(bListRemoveLast, count + 1, element);
      return element;
    }
    if (member == 'clear') {
      feBuiltin(bListClear, count + 1);
      return tVoid;
    }
    feAstError(call.token, 'unsupported List method ' + member);
  }
  if (type == tString) {
    if (member == 'codeUnitAt') {
      feBuiltin(bStringCodeUnit, count + 1);
      return tInt;
    }
    if (member == 'substring') {
      if (count == 1) feOperand(opInt, -1);
      feBuiltin(bStringSubstring, 3);
      return tString;
    }
    if (member == 'indexOf' || member == 'lastIndexOf') {
      if (count == 1) {
        if (member == 'indexOf')
          feOperand(opInt, 0);
        else
          feOperand(opInt, -1);
      }
      if (member == 'indexOf')
        feBuiltin(bStringIndexOf, 3);
      else
        feBuiltin(bStringLastIndexOf, 3);
      return tInt;
    }
    if (member == 'startsWith') {
      if (count == 1) feOperand(opInt, 0);
      feBuiltin(bStringStartsWith, 3);
      return tBool;
    }
    if (member == 'endsWith') {
      feBuiltin(bStringEndsWith, count + 1);
      return tBool;
    }
    feAstError(call.token, 'unsupported String method ' + member);
  }
  feAstError(call.token, 'unsupported member call ' + member);
  return tInt;
}

int feLowerCall(AstExpression call) {
  var callee = call.children[0];
  if (callee.kind == astName) {
    var name = callee.text;
    var function = feFindFunction(name);
    if (function >= 0) {
      var count = feLowerArguments(call, 1);
      if (functions[function].parameters != count) {
        feAstError(call.token, 'argument count for ' + name);
      }
      feCall(function, count);
      return functions[function].result;
    }
    var owner = feClassId(name);
    if (owner >= 0) {
      feOperand(opDescriptor, owner);
      feBuiltinTyped(bObjectNew, 1, classType(owner));
      var count = feLowerArguments(call, 1);
      var constructor = feClassConstructors[owner];
      if (constructor >= 0) {
        if (functions[constructor].parameters != count + 1) {
          feAstError(call.token, 'constructor argument count for ' + name);
        }
        feCall(constructor, count + 1);
      } else if (count != 0) {
        feAstError(call.token, 'constructor argument count for ' + name);
      }
      return classType(owner);
    }
    return feLowerBuiltinCall(call);
  }
  if (callee.kind == astMember) {
    var receiver = callee.children[0];
    if (receiver.kind == astName &&
        feLocal(receiver.text) < 0 &&
        feGlobal(receiver.text) < 0 &&
        feClassId(receiver.text) < 0 &&
        (receiver.text == 'List' ||
            receiver.text == 'String' ||
            receiver.text == 'int' ||
            receiver.text == 'Pointer')) {
      return feLowerStaticCall(call);
    }
    return feLowerMemberCall(call);
  }
  feAstError(call.token, 'unsupported call target');
  return tInt;
}

int feLowerMember(AstExpression expression) {
  var type = feLowerExpression(expression.children[0]);
  var member = expression.text;
  if (feClassType(type)) {
    var owner = typeArgument(type);
    var getter = feMethod(owner, member, true);
    if (getter >= 0) {
      feCall(getter, 1);
      return functions[getter].result;
    }
    var field = feField(owner, member);
    feOperand(opInt, feFieldIndices[field]);
    var result = feFieldTypes[field];
    feBuiltinTyped(bObjectGet, 2, result);
    return result;
  }
  if (member == 'length' || member == 'isEmpty' || member == 'isNotEmpty') {
    if (type == tString)
      feBuiltin(bStringLength, 1);
    else
      feBuiltin(bListLength, 1);
    if (member != 'length') {
      feOperand(opInt, 0);
      if (member == 'isEmpty')
        feEmit(opEq);
      else
        feEmit(opNe);
      return tBool;
    }
    return tInt;
  }
  if (typeIsList(type) && (member == 'first' || member == 'last')) {
    if (member == 'first')
      feOperand(opInt, 0);
    else {
      feDuplicate(type);
      feBuiltin(bListLength, 1);
      feOperand(opInt, 1);
      feEmit(opSub);
    }
    var element = typeArgument(type);
    feBuiltinTyped(bListGet, 2, element);
    return element;
  }
  feAstError(expression.token, 'unsupported property ' + member);
  return tInt;
}

FeLvalue feLowerLvalue(AstExpression expression) {
  if (expression.kind == astName) {
    return FeLvalue(
      expression.text,
      feVariableType(expression.text),
      0,
      -1,
      -1,
    );
  }
  var receiverType = feLowerExpression(expression.children[0]);
  var container = 1;
  var type = tInt;
  if (expression.kind == astIndex) {
    feLowerExpression(expression.children[1]);
    type = typeArgument(receiverType);
  } else if (expression.kind == astMember) {
    var field = feField(typeArgument(receiverType), expression.text);
    feOperand(opInt, feFieldIndices[field]);
    type = feFieldTypes[field];
    container = 2;
  } else {
    feAstError(expression.token, 'expression is not assignable');
  }
  var index = feTemp(tInt);
  feOperand(opStoreLocal, index);
  var receiver = feTemp(receiverType);
  feOperand(opStoreLocal, receiver);
  return FeLvalue('', type, container, receiver, index);
}

void feReadLvalue(FeLvalue target) {
  if (target.container == 0) {
    feLoad(target.name);
    return;
  }
  feOperand(opLoadLocal, target.receiver);
  feOperand(opLoadLocal, target.index);
  if (target.container == 1)
    feBuiltinTyped(bListGet, 2, target.type);
  else
    feBuiltinTyped(bObjectGet, 2, target.type);
}

void feWriteLvalue(FeLvalue target) {
  if (target.container == 0) {
    feDuplicate(target.type);
    feStore(target.name);
    return;
  }
  var value = feTemp(target.type);
  feOperand(opStoreLocal, value);
  feOperand(opLoadLocal, target.receiver);
  feOperand(opLoadLocal, target.index);
  feOperand(opLoadLocal, value);
  if (target.container == 1)
    feBuiltinTyped(bListSet, 3, target.type);
  else
    feBuiltinTyped(bObjectSet, 3, target.type);
}

int feLowerAssignment(AstExpression expression, bool postfix) {
  var target = feLowerLvalue(expression.children[0]);
  var op = expression.text;
  var increment = op == '++' || op == '--';
  var previous = -1;
  if (op != '=') {
    feReadLvalue(target);
    if (postfix) {
      previous = feTemp(target.type);
      feDuplicate(target.type);
      feOperand(opStoreLocal, previous);
    }
  }
  if (increment) {
    feOperand(opInt, 1);
    if (op == '++')
      feEmit(opAdd);
    else
      feEmit(opSub);
  } else {
    var right = feLowerExpression(expression.children[1]);
    if (op != '=')
      feCombine(op.substring(0, op.length - 1), target.type, right);
  }
  feWriteLvalue(target);
  if (postfix) {
    feEmit(opPop);
    feOperand(opLoadLocal, previous);
  }
  return target.type;
}

int feLowerExpression(AstExpression expression) {
  var kind = expression.kind;
  if (kind == astInteger) {
    feOperand(opInt, int.parse(expression.text));
    return tInt;
  }
  if (kind == astString) {
    feOperand(opString, feString(expression.text));
    return tString;
  }
  if (kind == astBoolean || kind == astNull) {
    var value = 0;
    if (expression.text == 'true') value = 1;
    feInteger(value, tBool);
    return tBool;
  }
  if (kind == astName) {
    var type = feVariableType(expression.text);
    feLoad(expression.text);
    return type;
  }
  if (kind == astList) return feLowerList(expression);
  if (kind == astMember) return feLowerMember(expression);
  if (kind == astCall) return feLowerCall(expression);
  if (kind == astIndex) {
    var receiver = feLowerExpression(expression.children[0]);
    feLowerExpression(expression.children[1]);
    if (receiver == tString) {
      feDuplicate(tInt);
      feOperand(opInt, 1);
      feEmit(opAdd);
      feBuiltin(bStringSubstring, 3);
      return tString;
    }
    var type = typeArgument(receiver);
    feBuiltinTyped(bListGet, 2, type);
    return type;
  }
  if (kind == astAssignment || kind == astPostfix) {
    return feLowerAssignment(expression, kind == astPostfix);
  }
  if (kind == astUnary) {
    var op = expression.text;
    if (op == '++' || op == '--') return feLowerAssignment(expression, false);
    var type = feLowerExpression(expression.children[0]);
    if (op == '+') return type;
    if (op == '-') {
      feEmit(opNeg);
      return tInt;
    }
    if (op == '~') {
      feEmit(opBitNot);
      return tInt;
    }
    feEmit(opNot);
    return tBool;
  }
  if (kind == astBinary) {
    var left = feLowerExpression(expression.children[0]);
    var op = expression.text;
    if (op == '&&' || op == '||') {
      feDuplicate(tBool);
      var otherwise = feJump(opJumpFalse);
      if (op == '&&') {
        feEmit(opPop);
        feLowerExpression(expression.children[1]);
        fePatch(otherwise, ir.length);
      } else {
        var done = feJump(opJump);
        fePatch(otherwise, ir.length);
        feEmit(opPop);
        feLowerExpression(expression.children[1]);
        fePatch(done, ir.length);
      }
      return tBool;
    }
    var right = feLowerExpression(expression.children[1]);
    return feCombine(op, left, right);
  }
  if (kind == astConditional) {
    feLowerExpression(expression.children[0]);
    var otherwise = feJump(opJumpFalse);
    var type = feLowerExpression(expression.children[1]);
    var done = feJump(opJump);
    fePatch(otherwise, ir.length);
    feLowerExpression(expression.children[2]);
    fePatch(done, ir.length);
    return type;
  }
  feAstError(expression.token, 'unsupported expression');
  return tInt;
}

int feExpression() {
  var parser = Parser(feTokens, feAt, fePendingTypeClosers);
  var expression = parseExpression(parser);
  feAt = parser.position;
  fePendingTypeClosers = parser.pendingClosers;
  return feLowerExpression(expression);
}

void feLowerVariable(AstVariable variable) {
  feAt = variable.token;
  var type = 0;
  if (variable.type.name != '') type = feLowerType(variable.type);
  var value = tInt;
  if (variable.initializer.length != 0)
    value = feLowerExpression(variable.initializer[0]);
  else
    feInteger(0, type);
  if (type == 0) type = value;
  var slot = feTemp(type);
  feLocalNames.add(variable.name);
  feLocalTypes.add(type);
  feLocalSlots.add(slot);
  feOperand(opStoreLocal, slot);
}

void feLoopEnd(int breakBase, int continueBase, int end, int repeat) {
  while (feBreaks.length > breakBase) fePatch(feBreaks.removeLast(), end);
  while (feContinues.length > continueBase)
    fePatch(feContinues.removeLast(), repeat);
  feLoopBreaks.removeLast();
  feLoopContinues.removeLast();
}

void feLowerStatement(AstStatement statement) {
  feAt = statement.token;
  var kind = statement.kind;
  if (kind == astEmptyStatement) return;
  if (kind == astForInStatement) {
    feLowerForIn(statement);
    return;
  }
  if (kind == astDoWhileStatement) {
    feLowerDoWhile(statement);
    return;
  }
  if (kind == astBlockStatement) {
    var scope = feLocalNames.length;
    var i = 0;
    while (i < statement.children.length) {
      feLowerStatement(statement.children[i]);
      i++;
    }
    feScopeEnd(scope);
    return;
  }
  if (kind == astVariableStatement) {
    var i = 0;
    while (i < statement.variables.length) {
      feLowerVariable(statement.variables[i]);
      i++;
    }
    return;
  }
  if (kind == astExpressionStatement) {
    feLowerExpression(statement.expressions[0]);
    feEmit(opPop);
    return;
  }
  if (kind == astReturnStatement) {
    if (statement.expressions.length != 0)
      feLowerExpression(statement.expressions[0]);
    else if (feConstructors[feFunction] == 1)
      feOperand(opLoadLocal, 0);
    else
      feInteger(0, tVoid);
    feEmit(opReturn);
    return;
  }
  if (kind == astIfStatement) {
    feLowerExpression(statement.condition[0]);
    var otherwise = feJump(opJumpFalse);
    feLowerStatement(statement.children[0]);
    if (statement.children.length == 2) {
      var done = feJump(opJump);
      fePatch(otherwise, ir.length);
      feLowerStatement(statement.children[1]);
      fePatch(done, ir.length);
    } else {
      fePatch(otherwise, ir.length);
    }
    return;
  }
  if (kind == astWhileStatement || kind == astForStatement) {
    var scope = feLocalNames.length;
    if (kind == astForStatement) feLowerStatement(statement.children[0]);
    var repeat = ir.length;
    if (statement.condition.length != 0)
      feLowerExpression(statement.condition[0]);
    else
      feInteger(1, tBool);
    var exit = feJump(opJumpFalse);
    var breakBase = feBreaks.length;
    var continueBase = feContinues.length;
    feLoopBreaks.add(breakBase);
    feLoopContinues.add(continueBase);
    if (kind == astForStatement)
      feLowerStatement(statement.children[1]);
    else
      feLowerStatement(statement.children[0]);
    var update = ir.length;
    if (statement.update.length != 0) {
      feLowerExpression(statement.update[0]);
      feEmit(opPop);
    }
    feOperand(opJump, repeat);
    fePatch(exit, ir.length);
    feLoopEnd(breakBase, continueBase, ir.length, update);
    feScopeEnd(scope);
    return;
  }
  if (kind == astBreakStatement) {
    if (feLoopBreaks.isEmpty) feError('break outside loop');
    feBreaks.add(feJump(opJump));
    return;
  }
  if (kind == astContinueStatement) {
    if (feLoopContinues.isEmpty) feError('continue outside loop');
    feContinues.add(feJump(opJump));
    return;
  }
  feAstError(statement.token, 'unsupported statement');
}

void feStatement() {
  var parser = Parser(feTokens, feAt, fePendingTypeClosers);
  var statement = parseStatement(parser);
  feLowerStatement(statement);
  feAt = parser.position;
  fePendingTypeClosers = parser.pendingClosers;
}

void fePrepareGlobals(int count) {
  var i = 0;
  while (i < count) {
    var initializer = GlobalInitializer(
      <int>[],
      <int>[],
      <int>[],
      0,
      -1,
      -1,
      -1,
    );
    if (imageKind == 0 && feRawGlobals[i] == 0 && _feLiteralTypes[i] == 0) {
      var type = globalTypes[i];
      initializer.getter = functions.length;
      functions.add(
        FunctionInfo(
          '#get:' + globalNames[i],
          0,
          0,
          0,
          type,
          <int>[],
          <int>[],
          feGlobalSources[i],
        ),
      );
      initializer.setter = functions.length;
      functions.add(
        FunctionInfo(
          '#set:' + globalNames[i],
          0,
          1,
          1,
          type,
          <int>[type],
          <int>[type],
          feGlobalSources[i],
        ),
      );
      initializer.state = globalNames.length;
      globalNames.add('#state:' + globalNames[i]);
      feGlobalSources.add(feGlobalSources[i]);
      globalTypes.add(tInt);
    }
    feGlobalInitializers.add(initializer);
    i++;
  }
}

void feInferGlobal(int global) {
  var initializer = feGlobalInitializers[global];
  if (initializer.code.isNotEmpty) return;
  if (initializer.result == -1)
    feError('cannot infer global type ' + globalNames[global]);
  initializer.result = -1;
  var previousCode = ir;
  var previousTypes = irTypes;
  var previousLocals = feSlotTypes;
  var previousNext = feNextLocal;
  var previousToken = feAt;
  var previousClosers = fePendingTypeClosers;
  var previousGlobal = feInitializingGlobal;
  ir = <int>[];
  irTypes = <int>[];
  feSlotTypes = <int>[];
  feNextLocal = 0;
  feInitializingGlobal = global;
  var type = globalTypes[global];
  var syntax = feGlobalNodes[global];
  if (syntax.initializer.length == 0) {
    if (type == 0) type = tInt;
    feInteger(0, type);
  } else {
    feAt = syntax.initializer[0].token;
    type = feLowerExpression(syntax.initializer[0]);
  }
  if (globalTypes[global] == 0) globalTypes[global] = type;
  initializer.result = globalTypes[global];
  initializer.code = ir;
  initializer.types = irTypes;
  initializer.locals = feSlotTypes;
  var getter = functions[initializer.getter];
  getter.result = initializer.result;
  var setter = functions[initializer.setter];
  setter.result = initializer.result;
  setter.parameterTypes[0] = initializer.result;
  setter.localTypes[0] = initializer.result;
  ir = previousCode;
  irTypes = previousTypes;
  feSlotTypes = previousLocals;
  feNextLocal = previousNext;
  feAt = previousToken;
  fePendingTypeClosers = previousClosers;
  feInitializingGlobal = previousGlobal;
}

void feAppendInitializer(GlobalInitializer initializer) {
  var base = ir.length;
  var position = 0;
  while (position < initializer.code.length) {
    var op = initializer.code[position];
    var width = irWidth(op);
    var word = 0;
    while (word < width) {
      var value = initializer.code[position + word];
      if (word == 1 && (op == opJump || op == opJumpFalse))
        value = value + base;
      ir.add(value);
      irTypes.add(initializer.types[position + word]);
      word++;
    }
    position = position + width;
  }
}

void feGenerateGlobals(int count) {
  var i = 0;
  while (i < count) {
    var initializer = feGlobalInitializers[i];
    if (initializer.getter >= 0) {
      var getter = functions[initializer.getter];
      getter.start = ir.length;
      feSlotTypes = initializer.locals;
      feNextLocal = initializer.locals.length;
      feOperand(opLoadGlobal, initializer.state);
      feOperand(opInt, 2);
      feEmit(opEq);
      var incomplete = feJump(opJumpFalse);
      feOperand(opLoadGlobal, i);
      feEmit(opReturn);
      fePatch(incomplete, ir.length);
      feOperand(opLoadGlobal, initializer.state);
      feOperand(opInt, 1);
      feEmit(opEq);
      var begin = feJump(opJumpFalse);
      feCall(feFindFunction('rtInitializationError'), 0);
      feEmit(opPop);
      fePatch(begin, ir.length);
      feOperand(opInt, 1);
      feOperand(opStoreGlobal, initializer.state);
      feAppendInitializer(initializer);
      feOperand(opStoreGlobal, i);
      feOperand(opInt, 2);
      feOperand(opStoreGlobal, initializer.state);
      feOperand(opLoadGlobal, i);
      feEmit(opReturn);
      getter.locals = feNextLocal;
      getter.localTypes = feSlotTypes;
      var setter = functions[initializer.setter];
      setter.start = ir.length;
      feSlotTypes = <int>[globalTypes[i]];
      feNextLocal = 1;
      feOperand(opLoadLocal, 0);
      feOperand(opStoreGlobal, i);
      feOperand(opInt, 2);
      feOperand(opStoreGlobal, initializer.state);
      feOperand(opLoadLocal, 0);
      feEmit(opReturn);
      setter.locals = 1;
      setter.localTypes = feSlotTypes;
    }
    i++;
  }
}

void parseSource(SourceProgram source) {
  resetTypes();
  ir.clear();
  irTypes.clear();
  functions.clear();
  feSlotTypes = <int>[];
  globalNames.clear();
  globalTypes.clear();
  strings.clear();
  classSizes.clear();
  classPointerMasks.clear();
  feClassNames.clear();
  feClassSources.clear();
  feClassNodes.clear();
  feFieldNodes.clear();
  feClassFieldCounts.clear();
  feClassConstructors.clear();
  feFieldNames.clear();
  feFieldTypes.clear();
  feFieldClasses.clear();
  feFieldIndices.clear();
  feOwners.clear();
  feConstructors.clear();
  feFunctionNodes.clear();
  feParamFields.clear();
  exportNames.clear();
  exportFunctions.clear();
  exportParameters.clear();
  feNativeNames.clear();
  feNativeParams.clear();
  feInitializingGlobal = -1;
  feGlobalSources.clear();
  feGlobalNodes.clear();
  feRawGlobals.clear();
  feGlobalInitializers.clear();
  _feLiteralTypes.clear();
  _feLiteralValues.clear();
  feParamStarts.clear();
  feParamNames.clear();
  feParamTypes.clear();
  feLocalNames.clear();
  feLocalTypes.clear();
  feLocalSlots.clear();
  feBreaks.clear();
  feContinues.clear();
  feLoopBreaks.clear();
  feLoopContinues.clear();
  functions.add(
    FunctionInfo('__init', 0, 0, 0, tVoid, <int>[], <int>[], sourceUnknown),
  );
  feFunctionNodes.add(
    AstFunction(
      '__init',
      AstType('void', <AstType>[], 0),
      <AstParameter>[],
      <AstStatement>[],
      <AstExpression>[],
      false,
      0,
      false,
    ),
  );
  feParamStarts.add(0);
  feOwners.add(-1);
  feConstructors.add(0);
  feSources = source;
  entrySource = source.entry;
  feSymbols = SymbolTable(source, <DeclarationSymbol>[]);
  feTokens = source.tokens;
  feAt = 0;
  fePendingTypeClosers = 0;
  feRuntimeTokens = source.runtimeTokens;
  var syntax = parseUnit(Parser(feTokens, 0, 0));
  feCollectDeclarations(syntax);
  stringUnitBytes = 8;
  var runtimeGlobal = 0;
  while (runtimeGlobal < globalNames.length) {
    if (feRawGlobals[runtimeGlobal] == 1 &&
        globalNames[runtimeGlobal] == 'rtStringUnitBytes') {
      if (_feLiteralTypes[runtimeGlobal] != tInt ||
          (_feLiteralValues[runtimeGlobal] != 2 &&
              _feLiteralValues[runtimeGlobal] != 8)) {
        feError('runtime rtStringUnitBytes must be 2 or 8');
      }
      stringUnitBytes = _feLiteralValues[runtimeGlobal];
    }
    runtimeGlobal++;
  }
  var sourceFunctions = functions.length;
  var sourceGlobals = globalNames.length;
  fePrepareGlobals(sourceGlobals);
  var global = 0;
  while (global < sourceGlobals) {
    if (feGlobalInitializers[global].getter >= 0) feInferGlobal(global);
    global++;
  }
  feNextLocal = 0;
  feFunction = 0;
  var i = 0;
  while (i < sourceGlobals) {
    if (feGlobalInitializers[i].getter < 0 && _feLiteralTypes[i] == 0) {
      feInitializingGlobal = i;
      var variable = feGlobalNodes[i];
      if (variable.initializer.length == 0) {
        feInteger(0, globalTypes[i]);
      } else {
        var type = feLowerExpression(variable.initializer[0]);
        if (globalTypes[i] == 0) globalTypes[i] = type;
      }
      feOperand(opStoreGlobal, i);
    }
    i++;
  }
  feInitializingGlobal = -1;
  feInteger(0, tVoid);
  feEmit(opReturn);
  functions[0].locals = feNextLocal;
  functions[0].localTypes = feSlotTypes;
  var f = 1;
  while (f < sourceFunctions) {
    feFunction = f;
    var functionSyntax = feFunctionNodes[f];
    feAt = functionSyntax.token;
    functions[f].start = ir.length;
    feLocalNames = <String>[];
    feLocalTypes = <int>[];
    feLocalSlots = <int>[];
    feSlotTypes = <int>[];
    feNextLocal = 0;
    var start = feParamStarts[f];
    var p = 0;
    while (p < functions[f].parameters) {
      feLocalNames.add(feParamNames[start + p]);
      feLocalTypes.add(feParamTypes[start + p]);
      feLocalSlots.add(feTemp(feParamTypes[start + p]));
      p++;
    }
    if (feConstructors[f] == 1) {
      var names = feLocalNames;
      var types = feLocalTypes;
      var slots = feLocalSlots;
      feLocalNames = <String>[];
      feLocalTypes = <int>[];
      feLocalSlots = <int>[];
      var owner = feOwners[f];
      var field = 0;
      while (field < feFieldNames.length) {
        if (feFieldClasses[field] == owner &&
            feFieldNodes[field].initializer.length != 0) {
          feOperand(opLoadLocal, 0);
          feOperand(opInt, feFieldIndices[field]);
          feLowerExpression(feFieldNodes[field].initializer[0]);
          feBuiltinTyped(bObjectSet, 3, feFieldTypes[field]);
          feEmit(opPop);
        }
        field++;
      }
      feLocalNames = names;
      feLocalTypes = types;
      feLocalSlots = slots;
      p = 1;
      while (p < functions[f].parameters) {
        var field = feParamFields[start + p];
        if (field >= 0) {
          feOperand(opLoadLocal, 0);
          feOperand(opInt, field);
          feOperand(opLoadLocal, p);
          feBuiltinTyped(bObjectSet, 3, feParamTypes[start + p]);
          feEmit(opPop);
        }
        p++;
      }
      if (functionSyntax.body.length != 0)
        feLowerStatement(functionSyntax.body[0]);
      feOperand(opLoadLocal, 0);
      feEmit(opReturn);
    } else if (functionSyntax.arrow.length != 0) {
      var type = feLowerExpression(functionSyntax.arrow[0]);
      if (functionSyntax.result.name == '') functions[f].result = type;
      feEmit(opReturn);
    } else {
      if (functionSyntax.body.length != 0)
        feLowerStatement(functionSyntax.body[0]);
      feInteger(0, functions[f].result);
      feEmit(opReturn);
    }
    functions[f].locals = feNextLocal;
    functions[f].localTypes = feSlotTypes;
    f++;
  }
  feGenerateGlobals(sourceGlobals);
}

void feLowerForIn(AstStatement statement) {
  var scope = feLocalNames.length;
  var iterableType = feLowerExpression(statement.expressions[0]);
  if (!typeIsList(iterableType)) {
    feAstError(statement.token, 'for-in currently requires a List');
  }
  var iterable = feTemp(iterableType);
  feOperand(opStoreLocal, iterable);
  var index = feTemp(tInt);
  feOperand(opInt, 0);
  feOperand(opStoreLocal, index);
  var declaration = statement.variables[0];
  var element = typeArgument(iterableType);
  var type = element;
  if (declaration.type.name != '') type = feLowerType(declaration.type);
  if (type != element) {
    feAstError(
      declaration.token,
      'for-in variable type must match the List element type',
    );
  }
  var variable = feTemp(type);
  feLocalNames.add(declaration.name);
  feLocalTypes.add(type);
  feLocalSlots.add(variable);
  var repeat = ir.length;
  feOperand(opLoadLocal, index);
  feOperand(opLoadLocal, iterable);
  feBuiltin(bListLength, 1);
  feEmit(opLt);
  var done = feJump(opJumpFalse);
  feOperand(opLoadLocal, iterable);
  feOperand(opLoadLocal, index);
  feBuiltinTyped(bListGet, 2, element);
  feOperand(opStoreLocal, variable);
  var breakBase = feBreaks.length;
  var continueBase = feContinues.length;
  feLoopBreaks.add(breakBase);
  feLoopContinues.add(continueBase);
  feLowerStatement(statement.children[0]);
  var update = ir.length;
  feOperand(opLoadLocal, index);
  feOperand(opInt, 1);
  feEmit(opAdd);
  feOperand(opStoreLocal, index);
  feOperand(opJump, repeat);
  fePatch(done, ir.length);
  feLoopEnd(breakBase, continueBase, ir.length, update);
  feScopeEnd(scope);
}

void feLowerDoWhile(AstStatement statement) {
  var scope = feLocalNames.length;
  var repeat = ir.length;
  var breakBase = feBreaks.length;
  var continueBase = feContinues.length;
  feLoopBreaks.add(breakBase);
  feLoopContinues.add(continueBase);
  feLowerStatement(statement.children[0]);
  var condition = ir.length;
  feLowerExpression(statement.condition[0]);
  var done = feJump(opJumpFalse);
  feOperand(opJump, repeat);
  fePatch(done, ir.length);
  feLoopEnd(breakBase, continueBase, ir.length, condition);
  feScopeEnd(scope);
}
