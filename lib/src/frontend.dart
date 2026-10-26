import 'ast.dart';
import 'parser.dart';
import 'ir.dart';
import 'types.dart';
import 'scanner.dart';
import 'source.dart';

class ControlLabel {
  String name;
  int target;
  bool loop;
  List<int> breaks;
  List<int> continues;
  int repeat;

  ControlLabel(
    this.name,
    this.target,
    this.loop,
    this.breaks,
    this.continues,
    this.repeat,
  );
}

List<ControlLabel> feLabels = <ControlLabel>[];

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
List<int> feBodies = <int>[];
List<int> feGlobalValues = <int>[];
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
  return tokenIs(feTokens[feAt], text);
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

void feDiscoverClasses() {
  for (var i = 0; i < feTokens.length - 1; i++) {
    if (feTokens[i].kind == tokenIdentifier && feTokens[i].text == 'class') {
      classType(feClassNames.length);
      feClassNames.add(feTokens[i + 1].text);
      feClassFieldCounts.add(0);
      feClassConstructors.add(-1);
      classSizes.add(16);
      classPointerMasks.add(0);
    }
  }
}

bool feTypeStart() {
  return feIs('int') ||
      feIs('String') ||
      feIs('bool') ||
      feIs('void') ||
      feIs('List') ||
      feIs('dynamic') ||
      feClassId(fePeek()) >= 0;
}

void feTypeClose() {
  if (fePendingTypeClosers > 0) {
    fePendingTypeClosers--;
    return;
  }
  if (feTake('>')) return;
  if (feTake('>>')) {
    fePendingTypeClosers = 1;
    return;
  }
  if (feTake('>>>')) {
    fePendingTypeClosers = 2;
    return;
  }
  feExpect('>');
}

int feType() {
  if (feTake('int')) return tInt;
  if (feTake('String')) return tString;
  if (feTake('bool')) return tBool;
  if (feTake('void')) return tVoid;
  if (feTake('dynamic')) return tInt;
  if (feTake('List')) {
    var element = tInt;
    if (feTake('<')) {
      element = feType();
      feTypeClose();
    }
    return listType(element);
  }
  var owner = feClassId(fePeek());
  if (owner >= 0) {
    feAt++;
    return classType(owner);
  }
  feError('unsupported type ' + fePeek());
  return tInt;
}

void feSkipGroup(String open, String close) {
  feExpect(open);
  var depth = 1;
  while (depth > 0 && !feIs('')) {
    if (feTake(open)) {
      depth++;
    } else if (feTake(close)) {
      depth--;
    } else {
      feAt++;
    }
  }
}

void feSkipExpression() {
  var parens = 0;
  var brackets = 0;
  var braces = 0;
  while (!feIs('')) {
    if (feIs(';') && parens == 0 && brackets == 0 && braces == 0) return;
    if (feTokens[feAt].kind != tokenString) {
      if (feIs('(')) parens++;
      if (feIs(')')) parens--;
      if (feIs('[')) brackets++;
      if (feIs(']')) brackets--;
      if (feIs('{')) braces++;
      if (feIs('}')) braces--;
    }
    feAt++;
  }
}

void feNativeTypedef() {
  var name = feName();
  feExpect('=');
  feExpect('Int64');
  feExpect('Function');
  feExpect('(');
  var count = 0;
  while (!feIs(')')) {
    feExpect('Int64');
    if (feTokens[feAt].kind == tokenIdentifier) feName();
    count++;
    if (!feTake(',')) break;
  }
  feExpect(')');
  feExpect(';');
  if (count > 8) feError('FFI callbacks support up to eight Int64 parameters');
  feNativeNames.add(name);
  feNativeParams.add(count);
}

void feFunctionTail() {
  if (feIs('{'))
    feSkipGroup('{', '}');
  else if (feTake('=>')) {
    feSkipExpression();
    feExpect(';');
  } else
    feExpect(';');
}

void feFunctionSignature(
  String name,
  int type,
  int owner,
  bool constructor,
  bool external,
) {
  var id = functions.length;
  var paramStart = feParamNames.length;
  var count = 0;
  if (owner >= 0) {
    feParamNames.add('this');
    feParamTypes.add(classType(owner));
    feParamFields.add(-1);
    count++;
  }
  while (!feIs(')')) {
    feTake('final');
    var paramType = tInt;
    var paramName = '';
    var field = -1;
    if (constructor && feTake('this')) {
      feExpect('.');
      paramName = feName();
      var entry = feField(owner, paramName);
      paramType = feFieldTypes[entry];
      field = feFieldIndices[entry];
    } else {
      paramType = feType();
      paramName = feName();
    }
    if (!external) {
      feParamNames.add(paramName);
      feParamTypes.add(paramType);
      feParamFields.add(field);
    }
    count++;
    if (!feTake(',')) break;
  }
  feExpect(')');
  if (external) {
    feExpect(';');
    return;
  }
  var parameterTypes = <int>[];
  for (var p = 0; p < count; p++) {
    parameterTypes.add(feParamTypes[paramStart + p]);
  }
  functions.add(
    FunctionInfo(
      name,
      0,
      count,
      count,
      type,
      parameterTypes,
      <int>[],
      feTokens[feAt].source,
    ),
  );
  feParamStarts.add(paramStart);
  feBodies.add(feAt);
  feOwners.add(owner);
  if (constructor) {
    feConstructors.add(1);
    feClassConstructors[owner] = id;
  } else {
    feConstructors.add(0);
  }
  if (!constructor && feIs(';')) feError('expected function body');
  feFunctionTail();
}

void feClassSignature() {
  var name = feName();
  var owner = feClassId(name);
  feExpect('{');
  var body = feAt;
  while (!feIs('}')) {
    feTake('final');
    if (feIs(name) && feTokens[feAt + 1].text == '(') {
      feAt++;
      feSkipGroup('(', ')');
      feFunctionTail();
    } else {
      var type = feType();
      var field = feName();
      if (feIs('(')) {
        feSkipGroup('(', ')');
        feFunctionTail();
      } else {
        feExpect(';');
        var index = feClassFieldCounts[owner];
        feClassFieldCounts[owner] = index + 1;
        classSizes[owner] = 16 + (index + 1) * 8;
        if (typeIsReference(type)) {
          classPointerMasks[owner] = classPointerMasks[owner] | (1 << index);
        }
        feFieldNames.add(field);
        feFieldTypes.add(type);
        feFieldClasses.add(owner);
        feFieldIndices.add(index);
      }
    }
  }
  feAt = body;
  while (!feIs('}')) {
    feTake('final');
    if (feIs(name) && feTokens[feAt + 1].text == '(') {
      feAt += 2;
      feFunctionSignature(name + '.new', classType(owner), owner, true, false);
    } else {
      var type = feType();
      var member = feName();
      if (feTake('(')) {
        feFunctionSignature(name + '.' + member, type, owner, false, false);
      } else {
        feExpect(';');
      }
    }
  }
  feExpect('}');
}

void _feRecordLiteralConstant(int global, int start, int end) {
  var count = end - start;
  var position = start;
  var sign = 1;
  if (count == 2 && feTokens[start].text == '-') {
    position = position + 1;
    sign = -1;
  } else if (count != 1) {
    return;
  }
  var type = 0;
  var value = 0;
  if (feTokens[position].kind == tokenInteger) {
    type = tInt;
    value = int.parse(feTokens[position].text) * sign;
  } else if (sign == 1 && feTokens[position].kind == tokenIdentifier) {
    if (feTokens[position].text == 'true') {
      type = tBool;
      value = 1;
    } else if (feTokens[position].text == 'false') {
      type = tBool;
    }
  }
  if (type == 0) return;
  if (globalTypes[global] != 0 && globalTypes[global] != type) return;
  _feLiteralTypes[global] = type;
  _feLiteralValues[global] = value;
  globalTypes[global] = type;
}

void feSignatures() {
  while (!feIs('')) {
    var declaration = feAt;
    if (feTake('class')) {
      feClassSignature();
      continue;
    }
    if (feTake('typedef')) {
      feNativeTypedef();
      continue;
    }
    if (feTake('import') || feTake('export') || feTake('library')) {
      while (!feIs(';') && !feIs('')) feAt++;
      feExpect(';');
      continue;
    }
    while (feTake('@')) {
      feName();
      while (feTake('.')) feName();
      if (feIs('(')) feSkipGroup('(', ')');
    }
    var external = feTake('external');
    var inferred = false;
    var constant = false;
    if (feTake('var')) {
      inferred = true;
    } else {
      constant = feTake('const');
      feTake('final');
    }
    var type = tInt;
    if (feTypeStart()) {
      type = feType();
    } else {
      inferred = true;
    }
    var name = feName();
    if (feTake('(')) {
      feFunctionSignature(name, type, -1, false, external);
    } else {
      globalNames.add(name);
      globalTypes.add(type);
      if (declaration < feRuntimeTokens)
        feRawGlobals.add(1);
      else
        feRawGlobals.add(0);
      _feLiteralTypes.add(0);
      _feLiteralValues.add(0);
      if (inferred) globalTypes[globalTypes.length - 1] = 0;
      if (feTake('=')) {
        var start = feAt;
        feGlobalValues.add(start);
        feSkipExpression();
        if (constant)
          _feRecordLiteralConstant(globalNames.length - 1, start, feAt);
      } else {
        feGlobalValues.add(-1);
      }
      feExpect(';');
    }
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
    var function = feFindFunction(feClassNames[owner] + '.' + member);
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
    var field = feField(typeArgument(type), member);
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
  if (kind == astInterpolation) return feLowerInterpolation(expression);
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
  if (kind == astLabeledStatement) {
    feLowerLabel(statement);
    return;
  }
  if (kind == astSwitchStatement) {
    feLowerSwitch(statement);
    return;
  }
  if (kind == astForInStatement) {
    feLowerForIn(statement);
    return;
  }
  if (kind == astDoWhileStatement) {
    feLowerDoWhile(statement);
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
    var updateIndex = 0;
    while (updateIndex < statement.update.length) {
      feLowerExpression(statement.update[updateIndex]);
      feEmit(opPop);
      updateIndex++;
    }
    feOperand(opJump, repeat);
    fePatch(exit, ir.length);
    feLabelRepeat(statement.token, update);
    feLoopEnd(breakBase, continueBase, ir.length, update);
    feScopeEnd(scope);
    return;
  }
  if (kind == astBreakStatement) {
    if (statement.expressions.isNotEmpty) {
      feLowerLabeledJump(statement, false);
      return;
    }
    if (feLoopBreaks.isEmpty) feError('break outside loop');
    feBreaks.add(feJump(opJump));
    return;
  }
  if (kind == astContinueStatement) {
    if (statement.expressions.isNotEmpty) {
      feLowerLabeledJump(statement, true);
      return;
    }
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
          feTokens[feGlobalValues[i]].source,
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
          feTokens[feGlobalValues[i]].source,
        ),
      );
      initializer.state = globalNames.length;
      globalNames.add('#state:' + globalNames[i]);
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
  if (feGlobalValues[global] < 0) {
    if (type == 0) type = tInt;
    feInteger(0, type);
  } else {
    feAt = feGlobalValues[global];
    type = feExpression();
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
  feClassFieldCounts.clear();
  feClassConstructors.clear();
  feFieldNames.clear();
  feFieldTypes.clear();
  feFieldClasses.clear();
  feFieldIndices.clear();
  feOwners.clear();
  feConstructors.clear();
  feParamFields.clear();
  exportNames.clear();
  exportFunctions.clear();
  exportParameters.clear();
  feNativeNames.clear();
  feNativeParams.clear();
  feInitializingGlobal = -1;
  feBodies.clear();
  feGlobalValues.clear();
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
  feLabels.clear();
  functions.add(FunctionInfo('__init', 0, 0, 0, tVoid, <int>[], <int>[], -1));
  feBodies.add(0);
  feParamStarts.add(0);
  feOwners.add(-1);
  feConstructors.add(0);
  entrySource = source.entry;
  feSources = source;
  feTokens = source.tokens;
  feAt = 0;
  fePendingTypeClosers = 0;
  feRuntimeTokens = source.runtimeTokens;
  feDiscoverClasses();
  feSignatures();
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
  for (var i = 0; i < sourceGlobals; i++) {
    if (feGlobalInitializers[i].getter >= 0 || _feLiteralTypes[i] != 0)
      continue;
    feInitializingGlobal = i;
    if (feGlobalValues[i] < 0) {
      feOperand(opInt, 0);
    } else {
      feAt = feGlobalValues[i];
      var type = feExpression();
      if (globalTypes[i] == 0) globalTypes[i] = type;
    }
    feOperand(opStoreGlobal, i);
  }
  feInitializingGlobal = -1;
  feInteger(0, tVoid);
  feEmit(opReturn);
  functions[0].locals = feNextLocal;
  functions[0].localTypes = feSlotTypes;
  for (var f = 1; f < sourceFunctions; f++) {
    feFunction = f;
    feAt = feBodies[f];
    functions[f].start = ir.length;
    feLocalNames.clear();
    feLocalTypes.clear();
    feLocalSlots.clear();
    feSlotTypes = <int>[];
    feNextLocal = 0;
    var start = feParamStarts[f];
    for (var p = 0; p < functions[f].parameters; p++) {
      feLocalNames.add(feParamNames[start + p]);
      feLocalTypes.add(feParamTypes[start + p]);
      feLocalSlots.add(feTemp(feParamTypes[start + p]));
    }
    if (feConstructors[f] == 1) {
      for (var p = 1; p < functions[f].parameters; p++) {
        var field = feParamFields[start + p];
        if (field >= 0) {
          feOperand(opLoadLocal, 0);
          feOperand(opInt, field);
          feOperand(opLoadLocal, p);
          feBuiltinTyped(bObjectSet, 3, feParamTypes[start + p]);
          feEmit(opPop);
        }
      }
      if (!feTake(';')) feStatement();
      feOperand(opLoadLocal, 0);
      feEmit(opReturn);
    } else if (feTake('=>')) {
      feExpression();
      feExpect(';');
      feEmit(opReturn);
    } else {
      feStatement();
      feInteger(0, functions[f].result);
      feEmit(opReturn);
    }
    functions[f].locals = feNextLocal;
    functions[f].localTypes = feSlotTypes;
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
  feLabelRepeat(statement.token, update);
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
  feLabelRepeat(statement.token, condition);
  feLoopEnd(breakBase, continueBase, ir.length, condition);
  feScopeEnd(scope);
}

bool feSwitchConstant(AstExpression expression) {
  if (expression.kind == astInteger ||
      expression.kind == astString ||
      expression.kind == astBoolean)
    return true;
  if (expression.kind == astUnary &&
      expression.text == '-' &&
      expression.children[0].kind == astInteger)
    return true;
  if (expression.kind == astName && feLocal(expression.text) < 0) {
    var global = feGlobal(expression.text);
    return global >= 0 && _feLiteralTypes[global] != 0;
  }
  return false;
}

void feLowerSwitch(AstStatement statement) {
  var scope = feLocalNames.length;
  var type = feLowerExpression(statement.expressions[0]);
  if (type != tInt && type != tString && type != tBool) {
    feAstError(
      statement.token,
      'switch currently requires int, String or bool',
    );
  }
  var value = feTemp(type);
  feOperand(opStoreLocal, value);
  List<int> entries = <int>[];
  var fallback = -1;
  var i = 0;
  while (i < statement.children.length) {
    var branch = statement.children[i];
    if (branch.expressions.isEmpty) {
      fallback = i;
      entries.add(-1);
    } else {
      var constant = branch.expressions[0];
      if (!feSwitchConstant(constant)) {
        feAstError(constant.token, 'case requires a supported constant');
      }
      feOperand(opLoadLocal, value);
      var caseType = feLowerExpression(constant);
      if (caseType != type) {
        feAstError(constant.token, 'case type must match the switch value');
      }
      feCombine('==', type, caseType);
      var next = feJump(opJumpFalse);
      entries.add(feJump(opJump));
      fePatch(next, ir.length);
    }
    i++;
  }
  var unmatched = feJump(opJump);
  var breakBase = feBreaks.length;
  feLoopBreaks.add(breakBase);
  i = 0;
  while (i < statement.children.length) {
    var branch = statement.children[i];
    if (entries[i] >= 0) fePatch(entries[i], ir.length);
    if (i == fallback) fePatch(unmatched, ir.length);
    var caseScope = feLocalNames.length;
    var child = 0;
    while (child < branch.children.length) {
      feLowerStatement(branch.children[child]);
      child++;
    }
    feScopeEnd(caseScope);
    if (branch.children.isNotEmpty) feBreaks.add(feJump(opJump));
    i++;
  }
  if (fallback < 0) fePatch(unmatched, ir.length);
  while (feBreaks.length > breakBase) fePatch(feBreaks.removeLast(), ir.length);
  feLoopBreaks.removeLast();
  feScopeEnd(scope);
}

void feLabelRepeat(int token, int target) {
  var i = 0;
  while (i < feLabels.length) {
    if (feLabels[i].target == token) feLabels[i].repeat = target;
    i++;
  }
}

void feLowerLabel(AstStatement statement) {
  var body = statement.children[0];
  var target = body;
  while (target.kind == astLabeledStatement) target = target.children[0];
  var kind = target.kind;
  var loop =
      kind == astForStatement ||
      kind == astForInStatement ||
      kind == astWhileStatement ||
      kind == astDoWhileStatement;
  var label = ControlLabel(
    statement.expressions[0].text,
    target.token,
    loop,
    <int>[],
    <int>[],
    -1,
  );
  feLabels.add(label);
  feLowerStatement(body);
  var i = 0;
  while (i < label.breaks.length) {
    fePatch(label.breaks[i], ir.length);
    i++;
  }
  i = 0;
  while (i < label.continues.length) {
    fePatch(label.continues[i], label.repeat);
    i++;
  }
  feLabels.removeLast();
}

void feLowerLabeledJump(AstStatement statement, bool repeat) {
  var name = statement.expressions[0].text;
  var i = feLabels.length - 1;
  while (i >= 0 && feLabels[i].name != name) i--;
  if (i < 0) feAstError(statement.token, 'unknown label ' + name);
  var label = feLabels[i];
  if (repeat) {
    if (!label.loop)
      feAstError(statement.token, 'continue requires a loop label');
    label.continues.add(feJump(opJump));
  } else {
    label.breaks.add(feJump(opJump));
  }
}

int feLowerInterpolation(AstExpression expression) {
  var i = 0;
  while (i < expression.children.length) {
    var part = expression.children[i];
    var type = feLowerExpression(part);
    if (part.kind == astNull) {
      feAstError(part.token, 'null interpolation is not supported yet');
    }
    if (type == tInt) {
      feBuiltin(bIntToString, 1);
    } else if (type == tBool) {
      var otherwise = feJump(opJumpFalse);
      feOperand(opString, feString('true'));
      var done = feJump(opJump);
      fePatch(otherwise, ir.length);
      feOperand(opString, feString('false'));
      fePatch(done, ir.length);
    } else if (feClassType(type)) {
      var owner = typeArgument(type);
      var method = feFindFunction(feClassNames[owner] + '.toString');
      if (method < 0) feAstError(part.token, 'interpolation requires toString');
      if (functions[method].parameters != 1 ||
          functions[method].result != tString) {
        feAstError(part.token, 'interpolation requires String toString()');
      }
      feCall(method, 1);
    } else if (type != tString) {
      feAstError(part.token, 'unsupported interpolation value');
    }
    if (i > 0) feBuiltin(bStringConcat, 2);
    i++;
  }
  return tString;
}
