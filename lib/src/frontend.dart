import 'ast.dart';
import 'parser.dart';
import 'ir.dart';
import 'layout.dart';
import 'types.dart';
import 'scanner.dart';
import 'source.dart';
import 'symbols.dart';

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

bool feClassType(int type) {
  return typeIsClass(type);
}

int feField(int owner, String name) {
  for (var i = 0; i < feFieldNames.length; i++) {
    if (feFieldClasses[i] == owner && feFieldNames[i] == name) return i;
  }
  feError('unknown field ' + classNames[owner] + '.' + name);
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
  if (syntax.external) {
    var source = feTokens[syntax.token].source;
    var primitive = fePrimitive(syntax.name);
    if (feRuntimeTokens == 0 || source != 0 || primitive == 0) {
      feAstError(
        syntax.token,
        'unsupported external declaration ' + syntax.name,
      );
    }
    if (owner >= 0 ||
        syntax.getter ||
        syntax.parameters.length != fePrimitiveArity(primitive)) {
      feAstError(syntax.token, 'invalid primitive signature ' + syntax.name);
    }
    feCheckPrimitiveType(syntax.result);
    var parameter = 0;
    while (parameter < syntax.parameters.length) {
      var syntaxParameter = syntax.parameters[parameter];
      if (syntaxParameter.fieldFormal)
        feAstError(syntaxParameter.token, 'primitive parameters require int');
      feCheckPrimitiveType(syntaxParameter.type);
      parameter++;
    }
    feDeclare(source, syntax.name, symbolBuiltin, primitive, syntax.token);
    return -1;
  }
  var id = functions.length;
  var start = feParamNames.length;
  var count = 0;
  var source = feTokens[syntax.token].source;
  var name = syntax.name;
  var result = tDynamic;
  if (constructor)
    result = classType(owner);
  else if (syntax.result.name != '')
    result = feLowerType(syntax.result);
  else if (owner >= 0 && syntax.name == 'toString' && !syntax.getter)
    result = tString;
  if (owner >= 0) {
    name = classNames[owner] + '.' + syntax.name;
    feParamNames.add('this');
    feParamTypes.add(classType(owner));
    feParamFields.add(-1);
    count++;
  }
  var p = 0;
  while (p < syntax.parameters.length) {
    var parameter = syntax.parameters[p];
    var type = tDynamic;
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
  if (globalTypes[global] >= 0 && globalTypes[global] != type) return;
  _feLiteralTypes[global] = type;
  _feLiteralValues[global] = value;
  globalTypes[global] = type;
}

void feCheckNativeInt64(AstType syntax) {
  var symbol = feTypeSymbol(syntax);
  if (symbol < 0 ||
      feSymbols.declarations[symbol].source != sourceFfi ||
      feSymbols.declarations[symbol].name != 'Int64') {
    feAstError(syntax.token, 'FFI callbacks currently require dart:ffi Int64');
  }
}

void feCollectDeclarations(AstUnit unit) {
  var i = 0;
  while (i < unit.classes.length) {
    var syntax = unit.classes[i];
    var source = feTokens[syntax.token].source;
    var owner = classNames.length;
    classType(owner);
    classNames.add(syntax.name);
    feClassSources.add(source);
    feClassNodes.add(syntax);
    feClassFieldCounts.add(0);
    feClassConstructors.add(-1);
    classSizes.add(objectHeaderBytes);
    classPointerMasks.add(0);
    classTaggedMasks.add(0);
    classToStringFunctions.add(-1);
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
      if (typeIsTagged(type)) {
        classTaggedMasks[i] = classTaggedMasks[i] | (1 << field);
      }
      field++;
    }
    feClassFieldCounts[i] = field;
    classSizes[i] = objectHeaderBytes + field * 8;
    i++;
  }
  i = 0;
  while (i < unit.variables.length) {
    var syntax = unit.variables[i];
    var source = feTokens[syntax.token].source;
    var type = -1;
    if (syntax.type.name != '') type = feLowerType(syntax.type);
    if (type < 0 && syntax.initializer.isEmpty) type = tDynamic;
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
    feCheckNativeInt64(syntax.result);
    var p = 0;
    while (p < syntax.parameterTypes.length) {
      feCheckNativeInt64(syntax.parameterTypes[p]);
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
    var toString = feMethod(i, 'toString', false);
    if (toString >= 0) {
      if (functions[toString].parameters != 1 ||
          functions[toString].result != tString) {
        feAstError(
          feFunctionNodes[toString].token,
          'toString must return String and have no parameters',
        );
      }
      classToStringFunctions[i] = toString;
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
  if (op == opInt || op == opMetadataAddress) irTypes[position] = tInt;
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
      id == bNativeStore64 ||
      id == bNativeLoad8 ||
      id == bNativeStore8 ||
      id == bNativeLoad16 ||
      id == bNativeStore16 ||
      id == bNativeSyscall ||
      id == bNativeTarget ||
      id == bNativeMetadataAddress ||
      id == bNativeCall1)
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

int feLocal(String name) {
  for (var i = feLocalNames.length - 1; i >= 0; i--) {
    if (feLocalNames[i] == name) return i;
  }
  return -1;
}

bool feImplicitMember(String name) {
  if (feInitializingGlobal >= 0 || feLocal('this') < 0 || feLocal(name) >= 0)
    return false;
  var owner = feOwners[feFunction];
  var field = 0;
  while (field < feFieldNames.length) {
    if (feFieldClasses[field] == owner && feFieldNames[field] == name)
      return true;
    field++;
  }
  return feMethod(owner, name, false) >= 0 || feMethod(owner, name, true) >= 0;
}

AstExpression feWithReceiver(AstExpression expression) {
  if (expression.kind != astName || !feImplicitMember(expression.text))
    return expression;
  var receiver = AstExpression(
    astName,
    'this',
    <AstExpression>[],
    <AstType>[],
    expression.token,
  );
  return AstExpression(
    astMember,
    expression.text,
    <AstExpression>[receiver],
    expression.typeArguments,
    expression.token,
  );
}

int feFindFunction(String name) {
  for (var i = 1; i < functions.length; i++) {
    if (functions[i].source == 0 && functions[i].name == name) return i;
  }
  feError('unknown runtime function ' + name);
  return -1;
}

int feResolveName(int token, String name, String prefix) {
  var symbol = resolveSymbol(feSymbols, feTokens[token].source, name, prefix);
  if (symbol == -2) feAstError(token, 'ambiguous name ' + name);
  return symbol;
}

bool feHasPrefix(int token, String prefix) {
  var source = feTokens[token].source;
  var imports = feSources.files[source].imports;
  var i = 0;
  while (i < imports.length) {
    if (!imports[i].exported && imports[i].prefix == prefix) return true;
    i++;
  }
  return false;
}

int feExpressionSymbol(AstExpression expression) {
  if (expression.kind == astName) {
    if (feLocal(expression.text) >= 0 || feImplicitMember(expression.text))
      return -1;
    return feResolveName(expression.token, expression.text, '');
  }
  if (expression.kind == astMember) {
    var receiver = expression.children[0];
    if (receiver.kind == astName &&
        feLocal(receiver.text) < 0 &&
        !feImplicitMember(receiver.text) &&
        feHasPrefix(receiver.token, receiver.text)) {
      return feResolveName(expression.token, expression.text, receiver.text);
    }
  }
  return -1;
}

int feTypeSymbol(AstType syntax) {
  var dot = syntax.name.indexOf('.');
  if (dot < 0) return feResolveName(syntax.token, syntax.name, '');
  return feResolveName(
    syntax.token,
    syntax.name.substring(dot + 1),
    syntax.name.substring(0, dot),
  );
}

int feGlobalType(int global) {
  if (globalTypes[global] < 0 && imageKind == 0 && feRawGlobals[global] == 0) {
    feInferGlobal(global);
  }
  return globalTypes[global];
}

void feLoadGlobalValue(int global) {
  if (_feLiteralTypes[global] != 0) {
    feInteger(_feLiteralValues[global], _feLiteralTypes[global]);
  } else if (imageKind == 0 && feRawGlobals[global] == 0) {
    feGlobalType(global);
    feCall(feGlobalInitializers[global].getter, 0);
  } else {
    feOperand(opLoadGlobal, global);
  }
}

void feStoreGlobalValue(int global) {
  if (imageKind == 0 &&
      feRawGlobals[global] == 0 &&
      _feLiteralTypes[global] == 0) {
    feCall(feGlobalInitializers[global].setter, 1);
    feEmit(opPop);
  } else {
    feOperand(opStoreGlobal, global);
  }
}

int feLoadDeclaration(int symbol, int token) {
  var declaration = feSymbols.declarations[symbol];
  if (declaration.kind == symbolGlobal) {
    var type = feGlobalType(declaration.target);
    feLoadGlobalValue(declaration.target);
    return type;
  }
  if (declaration.kind == symbolFunction &&
      feFunctionNodes[declaration.target].getter) {
    feCall(declaration.target, 0);
    return functions[declaration.target].result;
  }
  feAstError(token, 'declaration is not a value: ' + declaration.name);
  return tInt;
}

void feCheckPrivate(int owner, String name, int token) {
  if (name.startsWith('_') && feTokens[token].source != feClassSources[owner]) {
    feAstError(token, 'private member ' + name);
  }
}

int fePrimitive(String name) {
  if (name == 'nativeLoad64') return bNativeLoad64;
  if (name == 'nativeStore64') return bNativeStore64;
  if (name == 'nativeLoad8') return bNativeLoad8;
  if (name == 'nativeStore8') return bNativeStore8;
  if (name == 'nativeLoad16') return bNativeLoad16;
  if (name == 'nativeStore16') return bNativeStore16;
  if (name == 'nativeSyscall') return bNativeSyscall;
  if (name == 'nativeTarget') return bNativeTarget;
  if (name == 'nativeMetadataAddress') return bNativeMetadataAddress;
  if (name == 'nativeCall1') return bNativeCall1;
  return 0;
}

int fePrimitiveArity(int primitive) {
  if (primitive == bNativeLoad64 ||
      primitive == bNativeLoad8 ||
      primitive == bNativeLoad16 ||
      primitive == bNativeMetadataAddress)
    return 1;
  if (primitive == bNativeStore64 ||
      primitive == bNativeStore8 ||
      primitive == bNativeStore16 ||
      primitive == bNativeCall1)
    return 2;
  if (primitive == bNativeSyscall) return 7;
  if (primitive == bNativeTarget) return 0;
  return -1;
}

void feCheckPrimitiveType(AstType syntax) {
  var symbol = feTypeSymbol(syntax);
  if (symbol < 0 ||
      syntax.arguments.length != 0 ||
      feSymbols.declarations[symbol].source != sourceCore ||
      feSymbols.declarations[symbol].kind != symbolType ||
      feSymbols.declarations[symbol].name != 'int') {
    feAstError(syntax.token, 'primitive signature requires dart:core int');
  }
}

void feInstallSymbols() {
  declareSymbol(feSymbols, sourceCore, 'int', symbolType, tInt);
  declareSymbol(feSymbols, sourceCore, 'String', symbolType, tString);
  declareSymbol(feSymbols, sourceCore, 'bool', symbolType, tBool);
  declareSymbol(feSymbols, sourceCore, 'void', symbolType, tVoid);
  declareSymbol(feSymbols, sourceCore, 'dynamic', symbolType, tDynamic);
  declareSymbol(feSymbols, sourceCore, 'Object', symbolType, tObject);
  declareSymbol(feSymbols, sourceCore, 'Null', symbolType, tNull);
  declareSymbol(feSymbols, sourceCore, 'List', symbolType, -1);
  declareSymbol(feSymbols, sourceCore, 'print', symbolBuiltin, bPrintInt);
  declareSymbol(feSymbols, sourceFfi, 'Pointer', symbolType, tPointer);
  declareSymbol(feSymbols, sourceFfi, 'NativeFunction', symbolType, tPointer);
  declareSymbol(feSymbols, sourceFfi, 'Int64', symbolType, tInt);
  declareSymbol(feSymbols, sourceHost, 'hostRead', symbolBuiltin, bHostRead);
  declareSymbol(feSymbols, sourceHost, 'hostWrite', symbolBuiltin, bHostWrite);
  declareSymbol(
    feSymbols,
    sourceHost,
    'hostFinish',
    symbolBuiltin,
    bHostFinish,
  );
  declareSymbol(feSymbols, sourceHost, 'hostExit', symbolBuiltin, bHostExit);
  declareSymbol(
    feSymbols,
    sourceHost,
    'hostStdPath',
    symbolBuiltin,
    bHostStdPath,
  );
  declareSymbol(
    feSymbols,
    sourceHost,
    'hostTarget',
    symbolBuiltin,
    bHostTarget,
  );
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
  int type;
  int container;
  int receiver;
  int index;
  int local;
  int global;

  FeLvalue(
    this.type,
    this.container,
    this.receiver,
    this.index,
    this.local,
    this.global,
  );
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

int feValueOperation(String op) {
  if (op == '+') return bValueAdd;
  if (op == '-') return bValueSub;
  if (op == '*') return bValueMul;
  if (op == '~/') return bValueDiv;
  if (op == '%') return bValueMod;
  if (op == '&') return bValueAnd;
  if (op == '|') return bValueOr;
  if (op == '^') return bValueXor;
  if (op == '<<') return bValueShl;
  if (op == '>>') return bValueShr;
  if (op == '>>>') return bValueUshr;
  if (op == '==' || op == '!=') return bValueEq;
  if (op == '<') return bValueLt;
  if (op == '<=') return bValueLe;
  if (op == '>') return bValueGt;
  return bValueGe;
}

int feCombine(String op, int left, int right, int token) {
  if (op == '+' && left == tString && right == tString) {
    feBuiltin(bStringConcat, 2);
    return tString;
  }
  if ((op == '==' || op == '!=') && left == tString && right == tString) {
    feBuiltin(bStringEqual, 2);
    if (op == '!=') feEmit(opNot);
    return tBool;
  }
  var equal = op == '==' || op == '!=';
  var comparison = equal || op == '<' || op == '<=' || op == '>' || op == '>=';
  if (typeIsTagged(left) ||
      typeIsTagged(right) ||
      typeIsNullable(left) ||
      typeIsNullable(right) ||
      equal && left != right) {
    var savedRight = feTemp(right);
    feOperand(opStoreLocal, savedRight);
    feConvertValue(left, tDynamic, token);
    feOperand(opLoadLocal, savedRight);
    feConvertValue(right, tDynamic, token);
    var type = tDynamic;
    if (comparison) type = tBool;
    feBuiltinTyped(feValueOperation(op), 2, type);
    if (op == '!=') feEmit(opNot);
    return type;
  }
  if (left == tBool &&
      right == tBool &&
      (op == '&' || op == '|' || op == '^')) {
    feEmit(feBinaryOp(op));
    irTypes[ir.length - 1] = tBool;
    return tBool;
  }
  if (!equal && (left != tInt || right != tInt))
    feAstError(token, 'operator requires compatible operands');
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
  if (syntax.name.endsWith('?')) {
    return nullableType(
      feLowerType(
        AstType(
          syntax.name.substring(0, syntax.name.length - 1),
          syntax.arguments,
          syntax.token,
        ),
      ),
    );
  }
  if (syntax.name == 'void') return tVoid;
  if (syntax.name == 'dynamic') return tDynamic;
  var symbol = feTypeSymbol(syntax);
  if (symbol < 0) feAstError(syntax.token, 'unknown type ' + syntax.name);
  var declaration = feSymbols.declarations[symbol];
  if (declaration.kind == symbolClass) return classType(declaration.target);
  if (declaration.kind == symbolType) {
    if (declaration.target < 0) {
      var element = tDynamic;
      if (syntax.arguments.length != 0)
        element = feLowerType(syntax.arguments[0]);
      return listType(element);
    }
    return declaration.target;
  }
  feAstError(syntax.token, 'declaration is not a type: ' + syntax.name);
  return tInt;
}

int feConvertValue(int actual, int expected, int token) {
  if (actual == tVoid && expected != tVoid)
    feAstError(token, 'void expression cannot be used as a value');
  if (expected < 0 || actual == expected) return actual;
  if (typeIsSubtype(actual, expected)) {
    var builtin = bBoxRef;
    if (typeIsTagged(expected)) {
      if (actual == tInt) builtin = bBoxInt;
      if (actual == tBool) builtin = bBoxBool;
      if (actual == tPointer)
        feAstError(token, 'native addresses cannot be boxed as Dart values');
    }
    feBuiltinTyped(builtin, 1, expected);
    return expected;
  }
  if (actual == tDynamic || actual == tObject || typeIsNullable(actual)) {
    feBuiltinTyped(bValueCast, 1, expected);
    return expected;
  }
  feAstError(token, 'incompatible value type');
  return expected;
}

void feBooleanValue(int type, int token) {
  if (type == tVoid)
    feAstError(token, 'void expression cannot be used as a value');
  if (type == tBool) return;
  if (typeIsTagged(type) || typeIsNullable(type)) {
    feBuiltinTyped(bValueBool, 1, tBool);
    return;
  }
  feAstError(token, 'condition requires bool');
}

void feLowerBoolean(AstExpression expression) {
  feBooleanValue(feLowerExpression(expression), expression.token);
}

int feNonNullableValue(int type) {
  if (!typeIsNullable(type)) return type;
  var result = typeNonNullable(type);
  feBuiltinTyped(bValueCast, 1, result);
  return result;
}

int feLowerHint(AstExpression expression, int context) {
  if (expression.kind == astConditional)
    return feLowerConditional(expression, context);
  var type = -1;
  var listContext = context;
  if (listContext >= 0) listContext = typeNonNullable(listContext);
  if (listContext >= 0 && typeIsList(listContext)) {
    if (expression.kind == astList) type = feLowerList(expression, listContext);
    if (expression.kind == astCall) type = feLowerCall(expression, listContext);
  }
  if (type < 0) type = feLowerExpression(expression);
  return type;
}

int feLowerInContext(AstExpression expression, int context) {
  return feConvertValue(
    feLowerHint(expression, context),
    context,
    expression.token,
  );
}

int feLowerArguments(AstExpression call, int start, int function) {
  var argument = start;
  while (argument < call.children.length) {
    var expression = call.children[argument];
    if (expression.kind == astNamedArgument) {
      feAstError(
        expression.token,
        'unsupported named argument ' + expression.text,
      );
    }
    var context = -1;
    if (function >= 0) {
      var parameter = argument - start;
      if (feOwners[function] >= 0) parameter++;
      if (parameter < functions[function].parameterTypes.length)
        context = functions[function].parameterTypes[parameter];
    }
    feLowerInContext(expression, context);
    argument++;
  }
  return call.children.length - start;
}

int feLowerList(AstExpression expression, int context) {
  var element = -1;
  if (expression.typeArguments.length != 0) {
    element = feLowerType(expression.typeArguments[0]);
  } else if (context > 0 && typeIsList(context)) {
    element = typeArgument(context);
  }
  var values = <int>[];
  var types = <int>[];
  var inferred = -1;
  var item = 0;
  while (item < expression.children.length) {
    var child = expression.children[item];
    var type = -1;
    if (element < 0)
      type = feLowerHint(child, -1);
    else
      type = feLowerInContext(child, element);
    inferred = joinTypes(inferred, type);
    var slot = feTemp(type);
    feOperand(opStoreLocal, slot);
    values.add(slot);
    types.add(type);
    item++;
  }
  if (element < 0) element = inferred;
  if (element < 0) element = tDynamic;
  var type = listType(element);
  feBuiltinTyped(bListNew, 0, type);
  item = 0;
  while (item < values.length) {
    feDuplicate(type);
    feOperand(opLoadLocal, values[item]);
    feConvertValue(types[item], element, expression.children[item].token);
    feBuiltin(bListAdd, 2);
    feEmit(opPop);
    item++;
  }
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
  var signature = callee.typeArguments[0];
  var binding = feTypeSymbol(signature);
  if (binding < 0 || feSymbols.declarations[binding].kind != symbolNativeType) {
    feAstError(call.token, 'unknown FFI signature ' + signature.name);
  }
  var native = feSymbols.declarations[binding].target;
  var implementation = call.children[1];
  var target = feExpressionSymbol(implementation);
  if (target < 0 || feSymbols.declarations[target].kind != symbolFunction) {
    feAstError(
      implementation.token,
      'FFI callback requires a function declaration',
    );
  }
  var function = feSymbols.declarations[target].target;
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

int feMetadataMask(AstExpression expression) {
  if (expression.kind == astInteger) return int.parse(expression.text);
  var symbol = feExpressionSymbol(expression);
  if (symbol >= 0) {
    var declaration = feSymbols.declarations[symbol];
    if (declaration.kind == symbolGlobal &&
        _feLiteralTypes[declaration.target] == tInt)
      return _feLiteralValues[declaration.target];
  }
  feAstError(
    expression.token,
    'metadata feature mask must be an integer constant',
  );
  return 0;
}

int feBuiltinArgumentType(int builtin, int argument) {
  if (builtin == bHostRead || builtin == bHostFinish)
    return argument == 0 ? tString : tInt;
  if (builtin == bHostWrite) return argument == 0 ? tString : listType(tInt);
  if (builtin == bHostExit) return tInt;
  if (builtin == bStringFromCodes) return argument == 0 ? listType(tInt) : tInt;
  if (builtin == bIntParse ||
      builtin == bStringIndexOf ||
      builtin == bStringLastIndexOf ||
      builtin == bStringStartsWith ||
      builtin == bStringEndsWith)
    return argument == 0 ? tString : tInt;
  if (builtin == bStringCodeUnit || builtin == bStringSubstring) return tInt;
  return -1;
}

int feLowerBuiltinArguments(AstExpression call, int builtin) {
  var argument = 1;
  while (argument < call.children.length) {
    var expression = call.children[argument];
    if (expression.kind == astNamedArgument)
      feAstError(expression.token, 'unsupported named argument');
    feLowerInContext(expression, feBuiltinArgumentType(builtin, argument - 1));
    argument++;
  }
  return call.children.length - 1;
}

int feLowerBuiltinCall(AstExpression call, int builtin) {
  if (builtin == bNativeMetadataAddress) {
    if (call.children.length != 2)
      feAstError(call.token, 'primitive argument count');
    var mask = feMetadataMask(call.children[1]);
    if (mask < 1 || mask > 7)
      feAstError(call.token, 'metadata feature mask must be between 1 and 7');
    feOperand(opMetadataAddress, mask);
    return tInt;
  }
  if (builtin == bPrintInt) {
    if (call.children.length != 2)
      feAstError(call.token, 'argument count for print');
    var type = feLowerExpression(call.children[1]);
    if (type == tString)
      feBuiltin(bPrintString, 1);
    else if (type == tBool)
      feBuiltin(bPrintBool, 1);
    else if (type == tInt)
      feBuiltin(bPrintInt, 1);
    else {
      feConvertValue(type, tDynamic, call.token);
      feBuiltinTyped(bValueToString, 1, tString);
      feBuiltin(bPrintString, 1);
    }
    return tVoid;
  }
  var expected = fePrimitiveArity(builtin);
  var count = call.children.length - 1;
  if (expected >= 0) {
    if (count != expected) feAstError(call.token, 'primitive argument count');
    var argument = 1;
    while (argument < call.children.length) {
      var expression = call.children[argument];
      if (expression.kind == astNamedArgument)
        feAstError(expression.token, 'primitive arguments must be positional');
      feLowerInContext(expression, tInt);
      argument++;
    }
  } else {
    count = feLowerBuiltinArguments(call, builtin);
  }
  feBuiltin(builtin, count);
  return feBuiltinType(builtin);
}

int feLowerStaticCall(AstExpression call, int symbol, int context) {
  var callee = call.children[0];
  var receiver = callee.children[0];
  var declaration = feSymbols.declarations[symbol];
  var name = declaration.name;
  var member = callee.text;
  if (declaration.source == sourceFfi &&
      name == 'Pointer' &&
      member == 'fromFunction') {
    return feLowerPointerBinding(call);
  }
  if (declaration.source == sourceCore &&
      name == 'List' &&
      member == 'filled') {
    if (call.children.length < 3) {
      feAstError(call.token, 'List.filled requires length and value');
    }
    var element = -1;
    if (receiver.typeArguments.length != 0) {
      element = feLowerType(receiver.typeArguments[0]);
    } else if (context > 0 && typeIsList(context)) {
      element = typeArgument(context);
    }
    feLowerInContext(call.children[1], tInt);
    var valueType = -1;
    if (element < 0)
      valueType = feLowerHint(call.children[2], -1);
    else
      valueType = feLowerInContext(call.children[2], element);
    var argument = 3;
    while (argument < call.children.length) {
      var named = call.children[argument];
      if (named.kind != astNamedArgument || named.text != 'growable') {
        feAstError(named.token, 'unsupported List.filled argument');
      }
      feLowerBoolean(named.children[0]);
      feEmit(opPop);
      argument++;
    }
    if (element < 0) element = valueType;
    var type = listType(element);
    feBuiltinTyped(bListFilled, 2, type);
    return type;
  }
  if (declaration.source == sourceCore &&
      name == 'String' &&
      member == 'fromCharCodes') {
    var count = feLowerBuiltinArguments(call, bStringFromCodes);
    feBuiltin(bStringFromCodes, count);
    return tString;
  }
  if (declaration.source == sourceCore && name == 'int' && member == 'parse') {
    var count = feLowerBuiltinArguments(call, bIntParse);
    feBuiltin(bIntParse, count);
    return tInt;
  }
  feAstError(call.token, 'unsupported static call ' + name + '.' + member);
  return tInt;
}

int feLowerMemberCall(AstExpression call, AstExpression callee) {
  var receiver = callee.children[0];
  var member = callee.text;
  var type = feLowerExpression(receiver);
  if (member == 'toString' &&
      (!feClassType(type) || feMethod(typeArgument(type), member, false) < 0)) {
    if (call.children.length != 1)
      feAstError(call.token, 'argument count for toString');
    if (type == tInt)
      feBuiltin(bIntToString, 1);
    else if (type != tString) {
      feConvertValue(type, tDynamic, call.token);
      feBuiltinTyped(bValueToString, 1, tString);
    }
    return tString;
  }
  type = feNonNullableValue(type);
  if (feClassType(type)) {
    var owner = typeArgument(type);
    feCheckPrivate(owner, member, call.token);
    var function = feMethod(owner, member, false);
    if (function < 0) feAstError(call.token, 'unknown method ' + member);
    var count = feLowerArguments(call, 1, function) + 1;
    if (functions[function].parameters != count) {
      feAstError(call.token, 'method argument count for ' + member);
    }
    feCall(function, count);
    return functions[function].result;
  }
  if (typeIsList(type) && member == 'add') {
    if (call.children.length != 2)
      feAstError(call.token, 'argument count for List.add');
    var element = typeArgument(type);
    feLowerInContext(call.children[1], element);
    feBuiltin(bListAdd, 2);
    return tVoid;
  }
  if (typeIsList(type)) {
    if (call.children.length != 1)
      feAstError(call.token, 'List method requires no arguments');
    if (member == 'removeLast') {
      var element = typeArgument(type);
      feBuiltinTyped(bListRemoveLast, 1, element);
      return element;
    }
    if (member == 'clear') {
      feBuiltin(bListClear, 1);
      return tVoid;
    }
    feAstError(call.token, 'unsupported List method ' + member);
  }
  if (type == tString) {
    var builtin = 0;
    if (member == 'codeUnitAt') builtin = bStringCodeUnit;
    if (member == 'substring') builtin = bStringSubstring;
    if (member == 'indexOf') builtin = bStringIndexOf;
    if (member == 'lastIndexOf') builtin = bStringLastIndexOf;
    if (member == 'startsWith') builtin = bStringStartsWith;
    if (member == 'endsWith') builtin = bStringEndsWith;
    if (builtin == 0)
      feAstError(call.token, 'unsupported String method ' + member);
    var count = feLowerBuiltinArguments(call, builtin);
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

int feLowerCall(AstExpression call, int context) {
  var callee = feWithReceiver(call.children[0]);
  var symbol = feExpressionSymbol(callee);
  if (symbol >= 0) {
    var declaration = feSymbols.declarations[symbol];
    if (declaration.kind == symbolFunction) {
      var function = declaration.target;
      if (feFunctionNodes[function].getter) {
        feAstError(call.token, 'getter is not callable: ' + declaration.name);
      }
      var count = feLowerArguments(call, 1, function);
      if (functions[function].parameters != count) {
        feAstError(call.token, 'argument count for ' + declaration.name);
      }
      feCall(function, count);
      return functions[function].result;
    }
    if (declaration.kind == symbolBuiltin) {
      return feLowerBuiltinCall(call, declaration.target);
    }
    if (declaration.kind == symbolClass) {
      var owner = declaration.target;
      feOperand(opDescriptor, owner);
      feBuiltinTyped(bObjectNew, 1, classType(owner));
      var constructor = feClassConstructors[owner];
      var count = feLowerArguments(call, 1, constructor);
      if (functions[constructor].parameters != count + 1) {
        feAstError(
          call.token,
          'constructor argument count for ' + declaration.name,
        );
      }
      feCall(constructor, count + 1);
      return classType(owner);
    }
    feAstError(call.token, 'declaration is not callable: ' + declaration.name);
  }
  if (callee.kind == astMember) {
    var receiver = callee.children[0];
    var owner = feExpressionSymbol(receiver);
    if (owner >= 0 && feSymbols.declarations[owner].kind == symbolType) {
      return feLowerStaticCall(call, owner, context);
    }
    return feLowerMemberCall(call, callee);
  }
  feAstError(call.token, 'unknown call target ' + callee.text);
  return tInt;
}

int feLowerMember(AstExpression expression) {
  var symbol = feExpressionSymbol(expression);
  if (symbol >= 0) return feLoadDeclaration(symbol, expression.token);
  var type = feNonNullableValue(feLowerExpression(expression.children[0]));
  var member = expression.text;
  if (feClassType(type)) {
    var owner = typeArgument(type);
    feCheckPrivate(owner, member, expression.token);
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
    if (type != tString && !typeIsList(type))
      feAstError(expression.token, 'unsupported property ' + member);
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
  expression = feWithReceiver(expression);
  if (expression.kind == astName) {
    var local = feLocal(expression.text);
    if (local >= 0) {
      return FeLvalue(feLocalTypes[local], 0, -1, -1, feLocalSlots[local], -1);
    }
  }
  var symbol = feExpressionSymbol(expression);
  if (symbol >= 0) {
    var declaration = feSymbols.declarations[symbol];
    if (declaration.kind != symbolGlobal) {
      feAstError(
        expression.token,
        'declaration is not assignable: ' + declaration.name,
      );
    }
    return FeLvalue(
      feGlobalType(declaration.target),
      0,
      -1,
      -1,
      -1,
      declaration.target,
    );
  }
  if (expression.kind != astIndex && expression.kind != astMember) {
    feAstError(expression.token, 'expression is not assignable');
  }
  var receiverType = feNonNullableValue(
    feLowerExpression(expression.children[0]),
  );
  var container = 1;
  var type = tInt;
  if (expression.kind == astIndex) {
    if (!typeIsList(receiverType))
      feAstError(expression.token, 'indexed assignment requires List');
    feLowerInContext(expression.children[1], tInt);
    type = typeArgument(receiverType);
  } else {
    if (!feClassType(receiverType))
      feAstError(expression.token, 'field assignment requires an instance');
    var owner = typeArgument(receiverType);
    feCheckPrivate(owner, expression.text, expression.token);
    var field = feField(owner, expression.text);
    feOperand(opInt, feFieldIndices[field]);
    type = feFieldTypes[field];
    container = 2;
  }
  var index = feTemp(tInt);
  feOperand(opStoreLocal, index);
  var receiver = feTemp(receiverType);
  feOperand(opStoreLocal, receiver);
  return FeLvalue(type, container, receiver, index, -1, -1);
}

void feReadLvalue(FeLvalue target) {
  if (target.container == 0) {
    if (target.local >= 0)
      feOperand(opLoadLocal, target.local);
    else
      feLoadGlobalValue(target.global);
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
    if (target.local >= 0)
      feOperand(opStoreLocal, target.local);
    else
      feStoreGlobalValue(target.global);
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
  if (op == '=') {
    var source = expression.children[1];
    var type = feLowerHint(source, target.type);
    var value = feTemp(type);
    feOperand(opStoreLocal, value);
    feOperand(opLoadLocal, value);
    feConvertValue(type, target.type, source.token);
    feWriteLvalue(target);
    feEmit(opPop);
    feOperand(opLoadLocal, value);
    return type;
  }
  var increment = op == '++' || op == '--';
  var previous = -1;
  feReadLvalue(target);
  if (postfix) {
    previous = feTemp(target.type);
    feDuplicate(target.type);
    feOperand(opStoreLocal, previous);
  }
  if (increment) {
    feOperand(opInt, 1);
    var binary = '+';
    if (op == '--') binary = '-';
    var result = feCombine(binary, target.type, tInt, expression.token);
    feConvertValue(result, target.type, expression.token);
  } else {
    var right = feLowerInContext(expression.children[1], target.type);
    var result = feCombine(
      op.substring(0, op.length - 1),
      target.type,
      right,
      expression.token,
    );
    feConvertValue(result, target.type, expression.token);
  }
  feWriteLvalue(target);
  if (postfix) {
    feEmit(opPop);
    feOperand(opLoadLocal, previous);
  }
  return target.type;
}

int feLowerExpression(AstExpression expression) {
  expression = feWithReceiver(expression);
  var kind = expression.kind;
  if (kind == astInteger) {
    feOperand(opInt, int.parse(expression.text));
    return tInt;
  }
  if (kind == astString) {
    feOperand(opString, internString(expression.text));
    return tString;
  }
  if (kind == astNull) {
    feInteger(0, tNull);
    return tNull;
  }
  if (kind == astBoolean) {
    var value = 0;
    if (expression.text == 'true') value = 1;
    feInteger(value, tBool);
    return tBool;
  }
  if (kind == astName) {
    var local = feLocal(expression.text);
    if (local >= 0) {
      feOperand(opLoadLocal, feLocalSlots[local]);
      return feLocalTypes[local];
    }
    var symbol = feExpressionSymbol(expression);
    if (symbol < 0)
      feAstError(expression.token, 'unknown name ' + expression.text);
    return feLoadDeclaration(symbol, expression.token);
  }
  if (kind == astInterpolation) return feLowerInterpolation(expression);
  if (kind == astList) return feLowerList(expression, -1);
  if (kind == astMember) return feLowerMember(expression);
  if (kind == astCall) return feLowerCall(expression, -1);
  if (kind == astIndex) {
    var receiver = feNonNullableValue(
      feLowerExpression(expression.children[0]),
    );
    feLowerInContext(expression.children[1], tInt);
    if (receiver == tString) {
      feDuplicate(tInt);
      feOperand(opInt, 1);
      feEmit(opAdd);
      feBuiltin(bStringSubstring, 3);
      return tString;
    }
    if (!typeIsList(receiver))
      feAstError(expression.token, 'indexing requires String or List');
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
    if (op == '!') {
      feBooleanValue(type, expression.token);
      feEmit(opNot);
      return tBool;
    }
    if (typeIsTagged(type) || typeIsNullable(type)) {
      if (op == '+') {
        feBuiltinTyped(bValueCast, 1, tInt);
        return feConvertValue(tInt, tDynamic, expression.token);
      }
      var value = feTemp(type);
      feOperand(opStoreLocal, value);
      if (op == '-')
        feInteger(0, tInt);
      else
        feInteger(-1, tInt);
      feOperand(opLoadLocal, value);
      var binary = '-';
      if (op == '~') binary = '^';
      return feCombine(binary, tInt, type, expression.token);
    }
    if (type != tInt)
      feAstError(expression.token, 'unary operator requires int');
    if (op == '+') return type;
    if (op == '-') {
      feEmit(opNeg);
      return tInt;
    }
    if (op == '~') {
      feEmit(opBitNot);
      return tInt;
    }
    feAstError(expression.token, 'unsupported unary operator');
  }
  if (kind == astBinary) {
    var left = feLowerExpression(expression.children[0]);
    var op = expression.text;
    if (op == '&&' || op == '||') {
      feBooleanValue(left, expression.children[0].token);
      feDuplicate(tBool);
      var otherwise = feJump(opJumpFalse);
      if (op == '&&') {
        feEmit(opPop);
        feLowerBoolean(expression.children[1]);
        fePatch(otherwise, ir.length);
      } else {
        var done = feJump(opJump);
        fePatch(otherwise, ir.length);
        feEmit(opPop);
        feLowerBoolean(expression.children[1]);
        fePatch(done, ir.length);
      }
      return tBool;
    }
    var right = feLowerExpression(expression.children[1]);
    return feCombine(op, left, right, expression.token);
  }
  if (kind == astConditional) return feLowerConditional(expression, -1);
  feAstError(expression.token, 'unsupported expression');
  return tInt;
}

int feLowerConditional(AstExpression expression, int context) {
  feLowerBoolean(expression.children[0]);
  var otherwise = feJump(opJumpFalse);
  var type = feLowerHint(expression.children[1], context);
  var thenValue = feTemp(type);
  feOperand(opStoreLocal, thenValue);
  var thenConvert = feJump(opJump);
  fePatch(otherwise, ir.length);
  var elseType = feLowerHint(expression.children[2], context);
  var elseValue = feTemp(elseType);
  feOperand(opStoreLocal, elseValue);
  var elseConvert = feJump(opJump);
  var result = joinTypes(type, elseType);
  fePatch(thenConvert, ir.length);
  feOperand(opLoadLocal, thenValue);
  feConvertValue(type, result, expression.children[1].token);
  var done = feJump(opJump);
  fePatch(elseConvert, ir.length);
  feOperand(opLoadLocal, elseValue);
  feConvertValue(elseType, result, expression.children[2].token);
  fePatch(done, ir.length);
  return result;
}

void feLowerVariable(AstVariable variable) {
  feAt = variable.token;
  var type = -1;
  if (variable.type.name != '') type = feLowerType(variable.type);
  if (type < 0 && variable.initializer.isEmpty) type = tDynamic;
  var value = type;
  if (variable.initializer.length != 0)
    value = feLowerInContext(variable.initializer[0], type);
  else
    feInteger(0, type);
  if (type < 0) {
    if (value == tNull) value = feConvertValue(value, tDynamic, variable.token);
    type = value;
  }
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
    if (statement.expressions.length != 0) {
      var value = statement.expressions[0];
      var result = functions[feFunction].result;
      if (result == tVoid) {
        var type = feLowerHint(value, tVoid);
        if (type != tVoid && type != tNull)
          feAstError(value.token, 'void function cannot return a value');
        feConvertValue(type, tVoid, value.token);
      } else {
        feLowerInContext(value, result);
      }
    } else if (feConstructors[feFunction] == 1)
      feOperand(opLoadLocal, 0);
    else if (functions[feFunction].result == tVoid)
      feInteger(0, tVoid);
    else {
      feInteger(0, tNull);
      feConvertValue(tNull, functions[feFunction].result, statement.token);
    }
    feEmit(opReturn);
    return;
  }
  if (kind == astIfStatement) {
    feLowerBoolean(statement.condition[0]);
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
  if (kind == astWhileStatement || kind == astForStatement) {
    var scope = feLocalNames.length;
    if (kind == astForStatement) feLowerStatement(statement.children[0]);
    var repeat = ir.length;
    if (statement.condition.length != 0)
      feLowerBoolean(statement.condition[0]);
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
  var previousGlobal = feInitializingGlobal;
  ir = <int>[];
  irTypes = <int>[];
  feSlotTypes = <int>[];
  feNextLocal = 0;
  feInitializingGlobal = global;
  var type = globalTypes[global];
  var syntax = feGlobalNodes[global];
  if (syntax.initializer.length == 0) {
    if (type < 0) type = tDynamic;
    feInteger(0, type);
  } else {
    feAt = syntax.initializer[0].token;
    type = feLowerInContext(syntax.initializer[0], type);
  }
  if (globalTypes[global] < 0) {
    if (type == tNull) type = feConvertValue(type, tDynamic, syntax.token);
    globalTypes[global] = type;
  }
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
  classTaggedMasks.clear();
  classToStringFunctions.clear();
  classNames.clear();
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
  feLabels.clear();
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
  feRuntimeTokens = source.runtimeTokens;
  var paths = <String>[];
  var file = 0;
  while (file < source.files.length) {
    paths.add(source.files[file].path);
    file++;
  }
  var syntax = parseUnit(Parser(feTokens, 0, 0, paths));
  feInstallSymbols();
  feCollectDeclarations(syntax);
  if (imageKind == 0) {
    var marker = symbolOwnDeclaration(feSymbols, 0, 'rtAbiVersion');
    if (marker < 0 || feSymbols.declarations[marker].kind != symbolGlobal) {
      sourceError(
        feSources,
        feSources.files[0].tokens[0],
        'runtime must declare const int rtAbiVersion = ' +
            runtimeAbiVersion.toString(),
      );
    }
    var global = feSymbols.declarations[marker].target;
    if (_feLiteralTypes[global] != tInt ||
        _feLiteralValues[global] != runtimeAbiVersion) {
      feAstError(
        feGlobalNodes[global].token,
        'runtime rtAbiVersion must be const int ' +
            runtimeAbiVersion.toString(),
      );
    }
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
        var type = feLowerInContext(variable.initializer[0], globalTypes[i]);
        if (globalTypes[i] < 0) globalTypes[i] = type;
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
      var slot = feTemp(feParamTypes[start + p]);
      if (feConstructors[f] == 0 || feParamFields[start + p] < 0) {
        feLocalNames.add(feParamNames[start + p]);
        feLocalTypes.add(feParamTypes[start + p]);
        feLocalSlots.add(slot);
      }
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
          feLowerInContext(
            feFieldNodes[field].initializer[0],
            feFieldTypes[field],
          );
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
      feLowerInContext(functionSyntax.arrow[0], functions[f].result);
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
  var declaration = statement.variables[0];
  var context = -1;
  if (declaration.type.name != '')
    context = listType(feLowerType(declaration.type));
  var iterableType = feNonNullableValue(
    feLowerHint(statement.expressions[0], context),
  );
  if (!typeIsList(iterableType)) {
    feAstError(statement.token, 'for-in currently requires a List');
  }
  var iterable = feTemp(iterableType);
  feOperand(opStoreLocal, iterable);
  var index = feTemp(tInt);
  feOperand(opInt, 0);
  feOperand(opStoreLocal, index);
  var element = typeArgument(iterableType);
  var type = element;
  if (context >= 0) type = typeArgument(context);
  if (!typeIsSubtype(element, type) &&
      element != tDynamic &&
      element != tObject &&
      !typeIsNullable(element)) {
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
  feBuiltinTyped(bListGet, 2, type);
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
  feLowerBoolean(statement.condition[0]);
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
  var symbol = feExpressionSymbol(expression);
  if (symbol >= 0) {
    var declaration = feSymbols.declarations[symbol];
    return declaration.kind == symbolGlobal &&
        _feLiteralTypes[declaration.target] != 0;
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
      feCombine('==', type, caseType, constant.token);
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
  var slots = <int>[];
  var types = <int>[];
  var i = 0;
  while (i < expression.children.length) {
    var part = expression.children[i];
    var type = tString;
    var slot = -1;
    if (part.kind != astString) {
      type = feLowerExpression(part);
      slot = feTemp(type);
      feOperand(opStoreLocal, slot);
    }
    slots.add(slot);
    types.add(type);
    i++;
  }
  i = 0;
  while (i < expression.children.length) {
    var part = expression.children[i];
    var type = types[i];
    if (slots[i] < 0)
      feLowerExpression(part);
    else
      feOperand(opLoadLocal, slots[i]);
    if (type == tInt) {
      feBuiltin(bIntToString, 1);
    } else if (type == tBool) {
      var otherwise = feJump(opJumpFalse);
      feOperand(opString, internString('true'));
      var done = feJump(opJump);
      fePatch(otherwise, ir.length);
      feOperand(opString, internString('false'));
      fePatch(done, ir.length);
    } else if (feClassType(type) &&
        feMethod(typeArgument(type), 'toString', false) >= 0) {
      var owner = typeArgument(type);
      var method = feMethod(owner, 'toString', false);
      if (method < 0) feAstError(part.token, 'interpolation requires toString');
      if (functions[method].parameters != 1 ||
          functions[method].result != tString) {
        feAstError(part.token, 'interpolation requires String toString()');
      }
      feCall(method, 1);
    } else if (type != tString) {
      feConvertValue(type, tDynamic, part.token);
      feBuiltinTyped(bValueToString, 1, tString);
    }
    if (i > 0) feBuiltin(bStringConcat, 2);
    i++;
  }
  return tString;
}
