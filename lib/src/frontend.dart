import 'ast.dart';
import 'arguments.dart';
import 'binding.dart';
import 'constants.dart';
import 'constant_data.dart';
import 'resolve_type.dart';
import 'flow.dart';
import 'parser.dart';
import 'ir.dart';
import 'initialization.dart';
import 'layout.dart';
import 'members.dart';
import 'types.dart';
import 'typing.dart';
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
  List<FlowState> breakFlows = <FlowState>[];
  List<FlowState> continueFlows = <FlowState>[];

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

class ConstantObject {
  int getter;
  int slot;
  int state;
  int data;

  ConstantObject(this.getter, this.slot, this.state, this.data);
}

List<ConstantObject> feConstantObjects = <ConstantObject>[];
List<int> feConstantGetters = <int>[];

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
ConstantContext feConstants = ConstantContext(
  feSymbols,
  <AstVariable>[],
  <int>[],
);
List<AstFunction> feFunctionNodes = <AstFunction>[];
List<AstClass> feClassNodes = <AstClass>[];
List<ClassMembers> feMembers = <ClassMembers>[];
List<List<int>> feMemberFunctions = <List<int>>[];
List<int> feClassFieldStarts = <int>[];
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
List<int> feParamTypes = <int>[];
List<ConstantValue> feParamDefaults = <ConstantValue>[];
FunctionBindings feBindings = FunctionBindings(<LocalVariable>[], -1);
List<int> feBindingTypes = <int>[];
List<int> feBindingSlots = <int>[];
FlowState feFlow = flowCreate(0);
List<int> feBreaks = <int>[];
List<int> feContinues = <int>[];
List<FlowState> feBreakFlows = <FlowState>[];
List<FlowState> feContinueFlows = <FlowState>[];
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
List<int> feFieldTypes = <int>[];
List<int> feFieldIndices = <int>[];
List<int> feOwners = <int>[];
List<int> feConstructors = <int>[];
List<int> feParamFields = <int>[];

Never feError(String message) {
  sourceError(feSources, feTokens[feAt], message);
}

bool feClassType(int type) {
  return typeIsClass(type);
}

int feField(int owner, String name) {
  var index = lookupMember(feMembers[owner], name);
  if (index >= 0 && feMembers[owner].members[index].field >= 0)
    return feClassFieldStarts[owner] + feMembers[owner].members[index].field;
  feError('unknown field ' + classNames[owner] + '.' + name);
}

int feMethod(int owner, String name, bool getter) {
  var index = lookupMember(feMembers[owner], name);
  if (index < 0) return -1;
  var member = feMembers[owner].members[index];
  var method = member.method;
  if (getter) method = member.getter;
  if (method < 0) return -1;
  return feMemberFunctions[owner][method];
}

int feDeclare(int source, String name, int kind, int target, int token) {
  var symbol = declareSymbol(feSymbols, source, name, kind, target);
  if (symbol < 0) {
    feAstError(token, 'duplicate declaration ' + name);
  }
  return symbol;
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
      if (syntaxParameter.fieldFormal ||
          syntaxParameter.kind != astRequiredPositional)
        feAstError(syntaxParameter.token, 'primitive parameters require int');
      feCheckPrimitiveType(syntaxParameter.type);
      parameter++;
    }
    feDeclare(source, syntax.name, symbolBuiltin, primitive, syntax.token);
    return -1;
  }
  var id = functions.length;
  var start = feParamTypes.length;
  var count = 0;
  var source = feTokens[syntax.token].source;
  var name = syntax.name;
  var result = tDynamic;
  if (constructor)
    result = classType(owner);
  else if (syntax.result.name != '')
    result = resolveType(feSymbols, syntax.result);
  else if (owner >= 0 &&
      syntax.name == 'toString' &&
      !syntax.getter &&
      !syntax.setter)
    result = tString;
  if (owner >= 0) {
    name = classNames[owner] + '.' + syntax.name;
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
      if (!constructor)
        feAstError(
          parameter.token,
          'field-formal parameter requires a constructor',
        );
      var entry = feField(owner, parameter.name);
      type = feFieldTypes[entry];
      if (parameter.type.name != '') {
        type = resolveType(feSymbols, parameter.type);
        if (!typeIsSubtype(type, feFieldTypes[entry])) {
          feAstError(
            parameter.token,
            'field-formal type must be a subtype of the field type',
          );
        }
      }
      field = entry;
    } else if (parameter.type.name != '') {
      type = resolveType(feSymbols, parameter.type);
    }
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
  if (owner < 0) {
    if (syntax.getter || syntax.setter) {
      var symbol = declareAccessor(
        feSymbols,
        source,
        syntax.name,
        id,
        syntax.setter,
      );
      if (symbol < 0) {
        feAstError(syntax.token, 'duplicate declaration ' + syntax.name);
      }
    } else {
      feDeclare(source, syntax.name, symbolFunction, id, syntax.token);
    }
  }
  return id;
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
    classPointerMasks.add(<int>[]);
    classTaggedMasks.add(<int>[]);
    classToStringFunctions.add(-1);
    feDeclare(source, syntax.name, symbolClass, owner, syntax.token);
    if (source == feSources.core && !syntax.name.startsWith('_')) {
      feDeclare(sourceCore, syntax.name, symbolClass, owner, syntax.token);
    }
    i++;
  }
  i = 0;
  while (i < unit.classes.length) {
    feClassFieldStarts.add(feFieldTypes.length);
    feMembers.add(bindClassMembers(feSources, unit.classes[i]));
    feMemberFunctions.add(<int>[]);
    var fields = unit.classes[i].fields;
    var field = 0;
    while (field < fields.length) {
      var syntax = fields[field];
      if (syntax.type.name == '')
        feAstError(syntax.token, 'field requires a type');
      var type = resolveType(feSymbols, syntax.type);
      feFieldNodes.add(syntax);
      feFieldTypes.add(type);
      feFieldIndices.add(field);
      if ((field & 63) == 0) {
        classPointerMasks[i].add(0);
        classTaggedMasks[i].add(0);
      }
      var word = field ~/ 64;
      if (typeIsReference(type)) {
        classPointerMasks[i][word] =
            classPointerMasks[i][word] | (1 << (field & 63));
      }
      if (typeIsTagged(type)) {
        classTaggedMasks[i][word] =
            classTaggedMasks[i][word] | (1 << (field & 63));
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
    if (syntax.type.name != '') type = resolveType(feSymbols, syntax.type);
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
    var symbol = feDeclare(
      source,
      syntax.name,
      symbolGlobal,
      global,
      syntax.token,
    );
    feSymbols.declarations[symbol].writable =
        syntax.modifier != 'final' && syntax.modifier != 'const';
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
      feMemberFunctions[i].add(
        feRegisterFunction(syntax.methods[method], i, false),
      );
      method++;
    }
    var toString = feMethod(i, 'toString', false);
    if (toString >= 0) {
      if (functions[toString].parameters != 1 ||
          !typeIsSubtype(functions[toString].result, tString)) {
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
  if (op == opConstantData) irTypes[position] = tPointer;
  if (op == opTypeTest) irTypes[position] = tBool;
  if (op == opTypeCast) irTypes[position] = value;
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
  if (id == bHostExit || id == bHostFinish) return tNever;
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
      id == bNativeCall1 ||
      id == bNativeCall0 ||
      id == bNativeFramePointer)
    return tInt;
  if (id == bArguments) return listType(tString);
  return tVoid;
}

void feBuiltinTyped(int id, int count, int type) {
  feEmit(opBuiltin);
  irTypes[ir.length - 1] = type;
  feWord(id);
  feWord(count);
  if (type == tNever) flowUnreachable(feFlow);
}

void feBuiltin(int id, int count) {
  feBuiltinTyped(id, count, feBuiltinType(id));
}

void feCall(int function, int count) {
  feEmit(opCall);
  irTypes[ir.length - 1] = functions[function].result;
  feWord(function);
  feWord(count);
  if (functions[function].result == tNever) flowUnreachable(feFlow);
}

int feJump(int op) {
  feOperand(op, 0);
  return ir.length - 1;
}

void fePatch(int position, int target) {
  ir[position] = target;
}

void fePatchJumps(List<int> jumps, int target) {
  var i = 0;
  while (i < jumps.length) {
    fePatch(jumps[i], target);
    i++;
  }
}

void feBindLocal(int binding, int type, int slot) {
  feBindingTypes[binding] = type;
  feBindingSlots[binding] = slot;
  flowDeclare(feFlow, binding, type, true);
}

FlowState feJoinFlow(FlowState left, FlowState right) {
  return flowJoin(left, right, feBindingTypes);
}

void feNarrowValue(int stored, int promoted) {
  if (stored == promoted) return;
  var builtin = bBoxRef;
  if (promoted == tInt || promoted == tBool) builtin = bValueCast;
  feBuiltinTyped(builtin, 1, promoted);
}

int feReadLocal(int binding, int token) {
  var slot = feLocalSlot(binding, token);
  if (feFlow.assignments[binding] != flowAssigned) {
    feAstError(
      token,
      'local is not definitely assigned: ' + feBindings.variables[binding].name,
    );
  }
  feOperand(opLoadLocal, slot);
  var type = feFlow.types[binding];
  feNarrowValue(feBindingTypes[binding], type);
  return type;
}

int feLocalSlot(int binding, int token) {
  var slot = feBindingSlots[binding];
  if (slot < 0) {
    feAstError(
      token,
      'local referenced before declaration: ' +
          feBindings.variables[binding].name,
    );
  }
  return slot;
}

bool feImplicitMember(AstExpression expression) {
  if (feInitializingGlobal >= 0 ||
      feBindings.receiver < 0 ||
      expression.binding >= 0)
    return false;
  var name = expression.text;
  var owner = feOwners[feFunction];
  return lookupMember(feMembers[owner], name) >= 0;
}

AstExpression feWithReceiver(AstExpression expression) {
  if (expression.kind != astName || !feImplicitMember(expression))
    return expression;
  var receiver = AstExpression(
    astName,
    'this',
    <AstExpression>[],
    <AstType>[],
    expression.token,
  );
  receiver.binding = feBindings.receiver;
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
}

int feResolveName(int token, String name, String prefix, bool writing) {
  var source = feTokens[token].source;
  var symbol = -1;
  if (writing)
    symbol = resolveWriteSymbol(feSymbols, source, name, prefix);
  else
    symbol = resolveSymbol(feSymbols, source, name, prefix);
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

int feExpressionSymbol(AstExpression expression, bool writing) {
  if (expression.kind == astName) {
    if (expression.binding >= 0 || feImplicitMember(expression)) return -1;
    return feResolveName(expression.token, expression.text, '', writing);
  }
  if (expression.kind == astMember) {
    var receiver = expression.children[0];
    if (receiver.kind == astName &&
        receiver.binding < 0 &&
        !feImplicitMember(receiver) &&
        feHasPrefix(receiver.token, receiver.text)) {
      return feResolveName(
        expression.token,
        expression.text,
        receiver.text,
        writing,
      );
    }
  }
  return -1;
}

int feTypeSymbol(AstType syntax) {
  var dot = syntax.name.indexOf('.');
  if (dot < 0) return feResolveName(syntax.token, syntax.name, '', false);
  return feResolveName(
    syntax.token,
    syntax.name.substring(dot + 1),
    syntax.name.substring(0, dot),
    false,
  );
}

int feGlobalType(int global) {
  if (globalTypes[global] < 0 && imageKind == 0 && feRawGlobals[global] == 0) {
    feInferGlobal(global);
  }
  return globalTypes[global];
}

void feLoadGlobalValue(int global) {
  if (_feLiteralTypes[global] == tString) {
    feOperand(opString, _feLiteralValues[global]);
  } else if (_feLiteralTypes[global] != 0) {
    feInteger(_feLiteralValues[global], _feLiteralTypes[global]);
  } else if (feGlobalNodes[global].modifier == 'const') {
    var value = feConstants.values[global];
    feConstantValue(value, value.type, feGlobalNodes[global].token);
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
  if (declaration.kind == symbolProperty && declaration.target >= 0) {
    feCall(declaration.target, 0);
    return functions[declaration.target].result;
  }
  feAstError(token, 'declaration is not a value: ' + declaration.name);
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
  if (name == 'nativeCall0') return bNativeCall0;
  if (name == 'nativeFramePointer') return bNativeFramePointer;
  return 0;
}

int fePrimitiveArity(int primitive) {
  if (primitive == bNativeLoad64 ||
      primitive == bNativeLoad8 ||
      primitive == bNativeLoad16 ||
      primitive == bNativeMetadataAddress ||
      primitive == bNativeCall0)
    return 1;
  if (primitive == bNativeStore64 ||
      primitive == bNativeStore8 ||
      primitive == bNativeStore16 ||
      primitive == bNativeCall1)
    return 2;
  if (primitive == bNativeSyscall) return 7;
  if (primitive == bNativeTarget || primitive == bNativeFramePointer) return 0;
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
  declareSymbol(feSymbols, sourceCore, 'num', symbolType, tNum);
  declareSymbol(feSymbols, sourceCore, 'String', symbolType, tString);
  declareSymbol(feSymbols, sourceCore, 'bool', symbolType, tBool);
  declareSymbol(feSymbols, sourceCore, 'void', symbolType, tVoid);
  declareSymbol(feSymbols, sourceCore, 'dynamic', symbolType, tDynamic);
  declareSymbol(feSymbols, sourceCore, 'Object', symbolType, tObject);
  declareSymbol(feSymbols, sourceCore, 'Null', symbolType, tNull);
  declareSymbol(feSymbols, sourceCore, 'Never', symbolType, tNever);
  declareSymbol(feSymbols, sourceCore, 'List', symbolType, -1);
  declareSymbol(feSymbols, sourceCore, 'print', symbolBuiltin, bPrintInt);
  declareSymbol(
    feSymbols,
    sourceCore,
    'identical',
    symbolBuiltin,
    bValueIdentical,
  );
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

class FeLvalue {
  int type;
  int container;
  int receiver;
  int index;
  int binding;
  int global;
  int owner = -1;
  int member = -1;
  int reader = -1;
  int setter = -1;

  FeLvalue(
    this.type,
    this.container,
    this.receiver,
    this.index,
    this.binding,
    this.global,
  );
}

Never feAstError(int token, String message) {
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
  var result = typingBinary(op, left, right);
  if (result < 0) feAstError(token, 'operator requires compatible operands');
  if (result == tNever) {
    feEmit(opPop);
    return tNever;
  }
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
    var type = result;
    if (comparison)
      type = tBool;
    else if (result == tInt || result == tBool)
      type = tDynamic;
    feBuiltinTyped(feValueOperation(op), 2, type);
    if (op == '!=') feEmit(opNot);
    return feConvertValue(type, result, token);
  }
  if (left == tBool &&
      right == tBool &&
      (op == '&' || op == '|' || op == '^')) {
    feEmit(feBinaryOp(op));
    irTypes[ir.length - 1] = tBool;
    return tBool;
  }
  feEmit(feBinaryOp(op));
  return result;
}

int feConvertValue(int actual, int expected, int token) {
  if (actual == tVoid && expected != tVoid)
    feAstError(token, 'void expression cannot be used as a value');
  if (expected < 0 || actual == expected) return actual;
  if (!typingAssignable(actual, expected)) {
    feAstError(token, 'incompatible value type');
  }
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
  feBuiltinTyped(bValueCast, 1, expected);
  return expected;
}

void feBooleanValue(int type, int token) {
  if (type == tVoid)
    feAstError(token, 'void expression cannot be used as a value');
  if (!typingCondition(type)) feAstError(token, 'condition requires bool');
  if (type == tBool) return;
  feBuiltinTyped(bValueBool, 1, tBool);
}

void feLowerBoolean(AstExpression expression) {
  feBooleanValue(feLowerExpression(expression), expression.token);
}

void feConditionFact(AstExpression expression, bool truth) {
  if (expression.kind == astBoolean) {
    if ((expression.text == 'true') != truth) flowUnreachable(feFlow);
  } else if (expression.kind == astTypeTest) {
    var binding = expression.children[0].binding;
    if (binding < 0) return;
    var tested = resolveType(feSymbols, expression.typeArguments[0]);
    if (expression.text == 'is!') truth = !truth;
    if (truth)
      flowPromote(feFlow, binding, tested);
    else
      flowExclude(feFlow, binding, tested);
  } else if (expression.kind == astBinary &&
      (expression.text == '==' || expression.text == '!=')) {
    var left = expression.children[0];
    var right = expression.children[1];
    var binding = -1;
    if (left.kind == astName && right.kind == astNull) binding = left.binding;
    if (right.kind == astName && left.kind == astNull) binding = right.binding;
    if (binding >= 0) {
      flowNull(feFlow, binding, truth == (expression.text == '=='));
    }
  }
}

FlowState feConditionJumps(
  AstExpression expression,
  bool when,
  List<int> jumps,
) {
  if (expression.kind == astUnary && expression.text == '!') {
    return feConditionJumps(expression.children[0], !when, jumps);
  }
  if (expression.kind == astBinary &&
      (expression.text == '&&' || expression.text == '||')) {
    feFlow = flowSplit(feFlow);
    if (expression.text == '&&' && !when || expression.text == '||' && when) {
      var left = feConditionJumps(expression.children[0], when, jumps);
      var right = feConditionJumps(expression.children[1], when, jumps);
      var taken = flowUnsplit(feJoinFlow(left, right));
      feFlow = flowUnsplit(feFlow);
      return taken;
    } else {
      var skip = <int>[];
      var left = feConditionJumps(expression.children[0], !when, skip);
      var right = feConditionJumps(expression.children[1], when, jumps);
      feFlow = feJoinFlow(feFlow, left);
      fePatchJumps(skip, ir.length);
      feFlow = flowUnsplit(feFlow);
      return flowUnsplit(right);
    }
  }
  feLowerBoolean(expression);
  var after = flowCopy(feFlow);
  feConditionFact(expression, when);
  var taken = feFlow;
  feFlow = after;
  feConditionFact(expression, !when);
  var op = opJumpFalse;
  if (when) op = opJumpTrue;
  jumps.add(feJump(op));
  return taken;
}

int feNonNullableValue(int type, int token) {
  if (type == tVoid)
    feAstError(token, 'void expression cannot be used as a value');
  if (!typingReceiver(type)) {
    feAstError(token, 'member access requires a non-nullable receiver');
  }
  return type;
}

int feLowerHint(AstExpression expression, int context) {
  if (expression.kind == astPostfix && expression.text == '!')
    return feLowerNullAssertion(expression, context);
  if (expression.kind == astList && expression.constant) {
    feConstants.localTypes = feFlow.types;
    var value = evaluateConstant(feConstants, expression, context, true);
    feConstantValue(value, value.type, expression.token);
    return value.type;
  }
  if (expression.kind == astConditional)
    return feLowerConditional(expression, context);
  if (expression.kind == astBinary && expression.text == '??')
    return feLowerCoalescing(expression, context);
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

void feCheckMetadataScope(AstExpression expression, int owner) {
  if (expression.kind == astName &&
      expression.binding < 0 &&
      lookupMember(feMembers[owner], expression.text) >= 0)
    feAstError(
      expression.token,
      'metadata cannot reference an instance member',
    );
  var i = 0;
  while (i < expression.children.length) {
    feCheckMetadataScope(expression.children[i], owner);
    i++;
  }
}

void feCheckMetadata(List<AstExpression> metadata, int owner) {
  if (metadata.isEmpty) return;
  feConstants.localTypes = feFlow.types;
  var i = 0;
  while (i < metadata.length) {
    var expression = metadata[i];
    if (owner >= 0 && expression.kind != astCall)
      feCheckMetadataScope(expression, owner);
    checkMetadataConstant(feConstants, expression);
    i++;
  }
}

void feCheckUnitMetadata(AstUnit syntax) {
  var i = 0;
  while (i < syntax.directives.length) {
    feCheckMetadata(syntax.directives[i].metadata, -1);
    i++;
  }
  i = 0;
  while (i < syntax.variables.length) {
    feCheckMetadata(syntax.variables[i].metadata, -1);
    i++;
  }
  i = 0;
  while (i < syntax.typedefs.length) {
    feCheckMetadata(syntax.typedefs[i].metadata, -1);
    i++;
  }
  i = 0;
  while (i < syntax.classes.length) {
    var node = syntax.classes[i];
    feCheckMetadata(node.metadata, -1);
    var field = 0;
    while (field < node.fields.length) {
      feCheckMetadata(node.fields[field].metadata, i);
      field++;
    }
    i++;
  }
}

void feResolveDefaults(int count) {
  var omitted = ConstantValue(tNull, tNull, 0, '');
  while (feParamDefaults.length < feParamTypes.length)
    feParamDefaults.add(omitted);
  var f = 1;
  while (f < count) {
    var syntax = feFunctionNodes[f];
    feCheckMetadata(syntax.metadata, feOwners[f]);
    var parameters = syntax.parameters;
    var offset = feParamStarts[f];
    if (feOwners[f] >= 0) offset++;
    var p = 0;
    while (p < parameters.length) {
      var parameter = parameters[p];
      feCheckMetadata(parameter.metadata, feOwners[f]);
      if (parameter.kind == astNamedParameter) {
        var name = parameterName(parameter);
        if (name == '' || name.startsWith('_'))
          feAstError(
            parameter.token,
            'named parameter must have a public name',
          );
        var previous = 0;
        while (previous < p) {
          if (parameters[previous].kind == astNamedParameter &&
              parameterName(parameters[previous]) == name)
            feAstError(parameter.token, 'duplicate named parameter ' + name);
          previous++;
        }
      }
      if (parameter.kind != astRequiredPositional && !parameter.required) {
        var value = omitted;
        var type = feParamTypes[offset + p];
        var expression = parameter.defaultValue;
        if (expression != null)
          value = evaluateConstant(feConstants, expression, type, false);
        if (!typingAssignable(value.type, type) ||
            !typeIsSubtype(value.kind, type))
          feAstError(
            parameter.token,
            'default value is incompatible with parameter type',
          );
        feParamDefaults[offset + p] = value;
      }
      p++;
    }
    f++;
  }
}

void feDefaultArgument(int parameter, int token) {
  feConstantValue(feParamDefaults[parameter], feParamTypes[parameter], token);
}

int feConstantGetter(ConstantValue value) {
  var key = value.integer;
  while (feConstantGetters.length <= key) feConstantGetters.add(-1);
  if (feConstantGetters[key] >= 0) return feConstantGetters[key];
  var kinds = <int>[];
  var values = <int>[];
  var i = 0;
  while (i < value.elements.length) {
    var child = value.elements[i];
    var kind = typeKindNull;
    var payload = child.integer;
    if (child.kind == tInt) kind = typeKindInt;
    if (child.kind == tBool) kind = typeKindBool;
    if (child.kind == tString) {
      kind = typeKindString;
      payload = internString(child.text);
    }
    if (typeIsList(child.kind)) {
      kind = typeKindList;
      payload = feConstantGetter(child);
    }
    kinds.add(kind);
    values.add(payload);
    i++;
  }
  var slot = globalNames.length;
  globalNames.add('#constant:' + key.toString());
  globalTypes.add(value.kind);
  var state = globalNames.length;
  globalNames.add('#constant-state:' + key.toString());
  globalTypes.add(tBool);
  var getter = functions.length;
  functions.add(
    FunctionInfo(
      '#constant:' + key.toString(),
      0,
      0,
      0,
      value.kind,
      <int>[],
      <int>[],
      sourceUnknown,
    ),
  );
  feConstantGetters[key] = getter;
  var data = constantLists.length;
  constantLists.add(ListConstantData(value.kind, kinds, values));
  feConstantObjects.add(ConstantObject(getter, slot, state, data));
  return getter;
}

void feConstantValue(ConstantValue value, int type, int token) {
  if (value.kind == tString)
    feOperand(opString, internString(value.text));
  else if (typeIsList(value.kind))
    feCall(feConstantGetter(value), 0);
  else
    feInteger(value.integer, value.kind);
  feConvertValue(value.kind, type, token);
}

void feGenerateConstantObjects() {
  var i = 0;
  while (i < feConstantObjects.length) {
    var object = feConstantObjects[i];
    functions[object.getter].start = ir.length;
    feOperand(opLoadGlobal, object.state);
    var initialize = feJump(opJumpFalse);
    feOperand(opLoadGlobal, object.slot);
    feEmit(opReturn);
    fePatch(initialize, ir.length);
    var type = constantLists[object.data].type;
    feOperand(opConstantData, object.data);
    feBuiltinTyped(bListFromData, 1, type);
    feDuplicate(type);
    feOperand(opStoreGlobal, object.slot);
    feInteger(1, tBool);
    feOperand(opStoreGlobal, object.state);
    feEmit(opReturn);
    i++;
  }
}

int feLowerArguments(AstExpression call, int start, int function) {
  if (call.typeArguments.length != 0)
    feAstError(call.token, 'nongeneric call does not accept type arguments');
  var parameters = feFunctionNodes[function].parameters;
  var offset = feParamStarts[function];
  if (feOwners[function] >= 0) offset++;
  if (call.children.length - start == parameters.length &&
      (parameters.isEmpty || parameters.last.kind != astNamedParameter)) {
    var argument = start;
    while (argument < call.children.length) {
      var expression = call.children[argument];
      if (expression.kind == astNamedArgument)
        feAstError(
          expression.token,
          'unknown named argument ' + expression.text,
        );
      feLowerInContext(expression, feParamTypes[offset + argument - start]);
      argument++;
    }
    return parameters.length;
  }
  var bindings = bindArguments(
    feSources,
    feFunctionNodes[function],
    call,
    start,
  );
  var values = List<int>.filled(parameters.length, -1);
  var argument = start;
  while (argument < call.children.length) {
    var expression = call.children[argument];
    if (expression.kind == astNamedArgument)
      expression = expression.children[0];
    var parameter = bindings[argument - start];
    var type = feParamTypes[offset + parameter];
    feLowerInContext(expression, type);
    var value = feTemp(type);
    feOperand(opStoreLocal, value);
    values[parameter] = value;
    argument++;
  }
  var parameter = 0;
  while (parameter < parameters.length) {
    if (values[parameter] >= 0)
      feOperand(opLoadLocal, values[parameter]);
    else
      feDefaultArgument(offset + parameter, call.token);
    parameter++;
  }
  return parameters.length;
}

int feLowerList(AstExpression expression, int context) {
  var element = -1;
  if (expression.typeArguments.length != 0) {
    element = resolveType(feSymbols, expression.typeArguments[0]);
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
  if (call.typeArguments.length != 1 || call.children.length < 2) {
    feAstError(call.token, 'FFI callback requires a signature and function');
  }
  var signature = call.typeArguments[0];
  var binding = feTypeSymbol(signature);
  if (binding < 0 || feSymbols.declarations[binding].kind != symbolNativeType) {
    feAstError(call.token, 'unknown FFI signature ' + signature.name);
  }
  var native = feSymbols.declarations[binding].target;
  var implementation = call.children[1];
  var target = feExpressionSymbol(implementation, false);
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
  if (functions[function].result != tInt)
    feAstError(
      implementation.token,
      'FFI callbacks currently require an int result',
    );
  var parameter = 0;
  while (parameter < feFunctionNodes[function].parameters.length) {
    if (feFunctionNodes[function].parameters[parameter].kind ==
            astNamedParameter ||
        functions[function].parameterTypes[parameter] != tInt)
      feAstError(
        implementation.token,
        'FFI callbacks currently require positional int parameters',
      );
    parameter++;
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
  feConstants.localTypes = feFlow.types;
  var value = evaluateConstant(feConstants, expression, tInt, false);
  if (value.type != tInt || value.kind != tInt)
    feAstError(
      expression.token,
      'metadata feature mask must be an integer constant',
    );
  return value.integer;
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
  if (call.typeArguments.length != 0)
    feAstError(call.token, 'nongeneric call does not accept type arguments');
  if (builtin == bValueIdentical) {
    if (call.children.length != 3)
      feAstError(call.token, 'argument count for identical');
    var argument = 1;
    while (argument < call.children.length) {
      var expression = call.children[argument];
      if (expression.kind == astNamedArgument)
        feAstError(expression.token, 'identical arguments must be positional');
      feLowerInContext(expression, tDynamic);
      argument++;
    }
    feBuiltinTyped(bValueIdentical, 2, tBool);
    return tBool;
  }
  if (builtin == bNativeMetadataAddress) {
    if (call.children.length != 2)
      feAstError(call.token, 'primitive argument count');
    var mask = feMetadataMask(call.children[1]);
    var allowed =
        metadataStrings | metadataLists | metadataValues | metadataRoots;
    if (mask < 1 || (mask & ~allowed) != 0)
      feAstError(call.token, 'unknown metadata feature mask');
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
  if (call.typeArguments.length != 0)
    feAstError(call.token, 'nongeneric call does not accept type arguments');
  if (declaration.source == sourceCore &&
      name == 'List' &&
      member == 'filled') {
    if (call.children.length < 3) {
      feAstError(call.token, 'List.filled requires length and value');
    }
    var element = -1;
    if (receiver.typeArguments.length != 0) {
      if (receiver.typeArguments.length != 1)
        feAstError(receiver.token, 'List requires one type argument');
      element = resolveType(feSymbols, receiver.typeArguments[0]);
    } else if (context > 0 && typeIsList(context)) {
      element = typeArgument(context);
    }
    feLowerInContext(call.children[1], tInt);
    var valueType = -1;
    if (element < 0)
      valueType = feLowerHint(call.children[2], -1);
    else
      valueType = feLowerInContext(call.children[2], element);
    var hasGrowable = false;
    var argument = 3;
    while (argument < call.children.length) {
      var named = call.children[argument];
      if (named.kind != astNamedArgument || named.text != 'growable') {
        feAstError(named.token, 'unsupported List.filled argument');
      }
      if (hasGrowable) feAstError(named.token, 'duplicate growable argument');
      hasGrowable = true;
      feLowerBoolean(named.children[0]);
      argument++;
    }
    if (!hasGrowable) feInteger(0, tBool);
    if (element < 0) element = valueType;
    var type = listType(element);
    feBuiltinTyped(bListFilled, 3, type);
    return type;
  }
  if (declaration.source == sourceCore &&
      name == 'String' &&
      member == 'fromCharCodes') {
    if (call.children.length != 2)
      feAstError(call.token, 'String.fromCharCodes requires one List argument');
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
}

int feLowerMemberCall(AstExpression call, AstExpression callee) {
  var receiver = callee.children[0];
  var member = callee.text;
  var type = feLowerExpression(receiver);
  if (type == tNever) return feLowerNeverArguments(call);
  if (member == 'toString' &&
      (!feClassType(type) || feMethod(typeArgument(type), member, false) < 0)) {
    if (call.typeArguments.length != 0)
      feAstError(call.token, 'nongeneric call does not accept type arguments');
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
  type = feNonNullableValue(type, receiver.token);
  if (feClassType(type)) {
    var owner = typeArgument(type);
    feCheckPrivate(owner, member, call.token);
    var function = feMethod(owner, member, false);
    if (function < 0) {
      var value = feReadMember(type, member, call.token);
      if (value == tNever) return feLowerNeverArguments(call);
      feAstError(call.token, 'member value is not callable');
    }
    var count = feLowerArguments(call, 1, function) + 1;
    feCall(function, count);
    return functions[function].result;
  }
  if (call.typeArguments.length != 0)
    feAstError(call.token, 'nongeneric call does not accept type arguments');
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
    var count = call.children.length - 1;
    if (count < 1 ||
        count > 2 ||
        (member == 'codeUnitAt' || member == 'endsWith') && count != 1)
      feAstError(call.token, 'argument count for String.' + member);
    var defaultReceiver = -1;
    if (count == 1 && (member == 'substring' || member == 'lastIndexOf')) {
      defaultReceiver = feTemp(tString);
      feDuplicate(tString);
      feOperand(opStoreLocal, defaultReceiver);
    }
    feLowerBuiltinArguments(call, builtin);
    if (member == 'codeUnitAt') {
      feBuiltin(bStringCodeUnit, count + 1);
      return tInt;
    }
    if (member == 'substring') {
      if (count == 1) {
        feOperand(opLoadLocal, defaultReceiver);
        feBuiltin(bStringLength, 1);
      }
      feBuiltin(bStringSubstring, 3);
      return tString;
    }
    if (member == 'indexOf' || member == 'lastIndexOf') {
      if (count == 1) {
        if (member == 'indexOf')
          feOperand(opInt, 0);
        else {
          feOperand(opLoadLocal, defaultReceiver);
          feBuiltin(bStringLength, 1);
        }
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
}

int feLowerNeverArguments(AstExpression call) {
  var i = 0;
  while (i < call.typeArguments.length) {
    resolveType(feSymbols, call.typeArguments[i]);
    i++;
  }
  var names = <String>[];
  i = 1;
  while (i < call.children.length) {
    var argument = call.children[i];
    if (argument.kind == astNamedArgument) {
      var name = 0;
      while (name < names.length) {
        if (names[name] == argument.text)
          feAstError(argument.token, 'duplicate named argument');
        name++;
      }
      names.add(argument.text);
      argument = argument.children[0];
    }
    feLowerInContext(argument, tDynamic);
    feEmit(opPop);
    i++;
  }
  return tNever;
}

int feLowerCall(AstExpression call, int context) {
  var callee = feWithReceiver(call.children[0]);
  var symbol = feExpressionSymbol(callee, false);
  if (symbol >= 0) {
    var declaration = feSymbols.declarations[symbol];
    if (declaration.kind == symbolFunction) {
      var function = declaration.target;
      var count = feLowerArguments(call, 1, function);
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
      feCall(constructor, count + 1);
      return classType(owner);
    }
    var value = feLoadDeclaration(symbol, callee.token);
    if (value == tNever) return feLowerNeverArguments(call);
    feAstError(call.token, 'declaration is not callable: ' + declaration.name);
  }
  if (callee.kind == astMember) {
    var receiver = callee.children[0];
    var owner = feExpressionSymbol(receiver, false);
    if (owner >= 0 && feSymbols.declarations[owner].kind == symbolType) {
      return feLowerStaticCall(call, owner, context);
    }
    return feLowerMemberCall(call, callee);
  }
  var value = feLowerExpression(callee);
  if (value == tNever) return feLowerNeverArguments(call);
  feAstError(call.token, 'unknown call target ' + callee.text);
}

int feLowerMember(AstExpression expression) {
  var symbol = feExpressionSymbol(expression, false);
  if (symbol >= 0) return feLoadDeclaration(symbol, expression.token);
  var type = feNonNullableValue(
    feLowerExpression(expression.children[0]),
    expression.children[0].token,
  );
  return feReadMember(type, expression.text, expression.token);
}

int feReadMember(int type, String member, int token) {
  if (type == tNever) return tNever;
  if (feClassType(type)) {
    var owner = typeArgument(type);
    feCheckPrivate(owner, member, token);
    var index = lookupMember(feMembers[owner], member);
    if (index < 0) feAstError(token, 'unknown member ' + member);
    return feReadBoundMember(owner, feMembers[owner].members[index], token);
  }
  if (member == 'length' || member == 'isEmpty' || member == 'isNotEmpty') {
    if (type != tString && !typeIsList(type))
      feAstError(token, 'unsupported property ' + member);
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
  feAstError(token, 'unsupported property ' + member);
}

int feReadBoundMember(int owner, MemberBinding member, int token) {
  if (member.getter >= 0) {
    var getter = feMemberFunctions[owner][member.getter];
    feCall(getter, 1);
    return functions[getter].result;
  }
  if (member.field >= 0) {
    var field = feClassFieldStarts[owner] + member.field;
    feOperand(opInt, feFieldIndices[field]);
    var result = feFieldTypes[field];
    feBuiltinTyped(bObjectGet, 2, result);
    return result;
  }
  feAstError(token, 'member has no getter: ' + member.name);
}

FeLvalue feLowerLvalue(AstExpression expression, bool reading) {
  expression = feWithReceiver(expression);
  if (expression.kind == astName) {
    var binding = expression.binding;
    if (binding >= 0) {
      feLocalSlot(binding, expression.token);
      if (feBindings.variables[binding].constant)
        feAstError(expression.token, 'cannot assign a constant');
      return FeLvalue(feBindingTypes[binding], 0, -1, -1, binding, -1);
    }
  }
  var symbol = feExpressionSymbol(expression, true);
  if (symbol >= 0) {
    var declaration = feSymbols.declarations[symbol];
    var reader = -1;
    if (reading) {
      reader = feExpressionSymbol(expression, false);
      if (reader < 0) feAstError(expression.token, 'declaration has no getter');
    }
    if (declaration.setter >= 0) {
      var setter = declaration.setter;
      var target = FeLvalue(
        feParamTypes[feParamStarts[setter]],
        5,
        -1,
        -1,
        -1,
        -1,
      );
      target.reader = reader;
      target.setter = setter;
      return target;
    }
    if (declaration.kind != symbolGlobal || !declaration.writable) {
      feAstError(
        expression.token,
        'declaration is not assignable: ' + declaration.name,
      );
    }
    var target = FeLvalue(
      feGlobalType(declaration.target),
      0,
      -1,
      -1,
      -1,
      declaration.target,
    );
    target.reader = reader;
    return target;
  }
  if (expression.kind != astIndex && expression.kind != astMember) {
    feAstError(expression.token, 'expression is not assignable');
  }
  var receiverType = feNonNullableValue(
    feLowerExpression(expression.children[0]),
    expression.children[0].token,
  );
  if (receiverType == tNever) {
    if (expression.kind == astIndex) {
      feLowerInContext(expression.children[1], tDynamic);
      feEmit(opPop);
    }
    var receiver = feTemp(tNever);
    feOperand(opStoreLocal, receiver);
    return FeLvalue(tDynamic, 3, receiver, -1, -1, -1);
  }
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
    var entry = lookupMember(feMembers[owner], expression.text);
    if (entry < 0)
      feAstError(expression.token, 'unknown member ' + expression.text);
    var member = feMembers[owner].members[entry];
    if (member.setter >= 0) {
      var setter = feMemberFunctions[owner][member.setter];
      var receiver = feTemp(receiverType);
      feOperand(opStoreLocal, receiver);
      var target = FeLvalue(
        feParamTypes[feParamStarts[setter] + 1],
        4,
        receiver,
        -1,
        -1,
        -1,
      );
      target.owner = owner;
      target.member = entry;
      return target;
    }
    if (member.field < 0)
      feAstError(expression.token, 'member has no setter: ' + member.name);
    var field = feClassFieldStarts[owner] + member.field;
    if (feFieldNodes[field].modifier == 'final')
      feAstError(expression.token, 'cannot assign a final field');
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

int feReadLvalue(FeLvalue target, int token) {
  if (target.container == 3) {
    feOperand(opLoadLocal, target.receiver);
    return tNever;
  }
  if (target.container == 0) {
    if (target.binding >= 0) return feReadLocal(target.binding, token);
    return feLoadDeclaration(target.reader, token);
  }
  if (target.container == 5) {
    return feLoadDeclaration(target.reader, token);
  }
  if (target.container == 4) {
    feOperand(opLoadLocal, target.receiver);
    return feReadBoundMember(
      target.owner,
      feMembers[target.owner].members[target.member],
      token,
    );
  }
  feOperand(opLoadLocal, target.receiver);
  feOperand(opLoadLocal, target.index);
  if (target.container == 1)
    feBuiltinTyped(bListGet, 2, target.type);
  else
    feBuiltinTyped(bObjectGet, 2, target.type);
  return target.type;
}

void feWriteFlow(FeLvalue target, int type) {
  if (target.binding >= 0) {
    flowWrite(feFlow, target.binding, target.type, type);
  }
}

void feWriteLvalue(FeLvalue target, int token) {
  if (target.binding >= 0 &&
      feBindings.variables[target.binding].finalVariable &&
      feFlow.assignments[target.binding] != flowUnassigned) {
    feAstError(token, 'final variable might already be assigned');
  }
  if (target.container == 3) return;
  if (target.container == 0) {
    feDuplicate(target.type);
    if (target.binding >= 0)
      feOperand(opStoreLocal, feBindingSlots[target.binding]);
    else
      feStoreGlobalValue(target.global);
    return;
  }
  if (target.container == 5) {
    feCall(target.setter, 1);
    return;
  }
  var value = feTemp(target.type);
  feOperand(opStoreLocal, value);
  feOperand(opLoadLocal, target.receiver);
  if (target.container == 4) {
    var member = feMembers[target.owner].members[target.member];
    var setter = feMemberFunctions[target.owner][member.setter];
    feOperand(opLoadLocal, value);
    feCall(setter, 2);
    return;
  }
  feOperand(opLoadLocal, target.index);
  feOperand(opLoadLocal, value);
  if (target.container == 1)
    feBuiltinTyped(bListSet, 3, target.type);
  else
    feBuiltinTyped(bObjectSet, 3, target.type);
}

int feLowerAssignment(AstExpression expression, bool postfix) {
  var op = expression.text;
  var target = feLowerLvalue(expression.children[0], op != '=');
  if (op == '??=') return feLowerCoalescingAssignment(expression, target);
  if (op == '=') {
    var source = expression.children[1];
    var type = feLowerHint(source, target.type);
    var value = feTemp(type);
    feOperand(opStoreLocal, value);
    feOperand(opLoadLocal, value);
    feConvertValue(type, target.type, source.token);
    feWriteLvalue(target, expression.token);
    feWriteFlow(target, type);
    feEmit(opPop);
    feOperand(opLoadLocal, value);
    return type;
  }
  var increment = op == '++' || op == '--';
  var previous = -1;
  var readType = feReadLvalue(target, expression.token);
  if (postfix) {
    previous = feTemp(readType);
    feDuplicate(readType);
    feOperand(opStoreLocal, previous);
  }
  var result = readType;
  if (increment) {
    feOperand(opInt, 1);
    var binary = '+';
    if (op == '--') binary = '-';
    result = feCombine(binary, readType, tInt, expression.token);
  } else {
    var right = feLowerHint(expression.children[1], readType);
    result = feCombine(
      op.substring(0, op.length - 1),
      readType,
      right,
      expression.token,
    );
  }
  var value = feTemp(result);
  feOperand(opStoreLocal, value);
  feOperand(opLoadLocal, value);
  feConvertValue(result, target.type, expression.token);
  feWriteLvalue(target, expression.token);
  feWriteFlow(target, result);
  feEmit(opPop);
  if (postfix)
    feOperand(opLoadLocal, previous);
  else
    feOperand(opLoadLocal, value);
  if (postfix) return readType;
  return result;
}

int feLowerCoalescingAssignment(AstExpression expression, FeLvalue target) {
  var left = feReadLvalue(target, expression.token);
  if (left == tVoid)
    feAstError(expression.token, 'void expression cannot be used as a value');
  if (left == tNever) flowUnreachable(feFlow);
  feFlow = flowSplit(feFlow);
  var value = -1;
  var present = -1;
  if (left == tNull) {
    feEmit(opPop);
  } else {
    value = feTemp(left);
    feOperand(opStoreLocal, value);
    if (typeCanBeNull(left)) {
      feOperand(opLoadLocal, value);
      feInteger(0, tNull);
      feEmit(opNe);
    } else {
      feInteger(1, tBool);
    }
    present = feJump(opJumpTrue);
  }
  var afterLeft = feFlow;
  feFlow = flowCopy(afterLeft);
  if (!typeCanBeNull(left)) flowUnreachable(feFlow);
  var source = expression.children[1];
  var context = target.type;
  if (target.binding >= 0) context = left;
  var right = feLowerHint(source, context);
  var assigned = feTemp(right);
  feOperand(opStoreLocal, assigned);
  feOperand(opLoadLocal, assigned);
  feConvertValue(right, target.type, source.token);
  feWriteLvalue(target, expression.token);
  feWriteFlow(target, right);
  feEmit(opPop);
  var result = typingCoalescing(left, right);
  feOperand(opLoadLocal, assigned);
  feConvertValue(right, result, source.token);
  if (left == tNull) {
    feFlow = flowUnsplit(feFlow);
    return result;
  }
  var rightFlow = feFlow;
  var done = feJump(opJump);
  fePatch(present, ir.length);
  feFlow = afterLeft;
  if (target.binding >= 0) flowNull(feFlow, target.binding, false);
  feOperand(opLoadLocal, value);
  var promoted = typeNonNullable(left);
  feNarrowValue(left, promoted);
  feConvertValue(promoted, result, expression.token);
  feFlow = flowUnsplit(feJoinFlow(feFlow, rightFlow));
  fePatch(done, ir.length);
  return result;
}

int feLowerNullAssertion(AstExpression expression, int context) {
  var source = expression.children[0];
  var type = feLowerHint(source, context);
  var result = typingNullAssertion(type);
  if (result < 0)
    feAstError(expression.token, 'void expression cannot be used as a value');
  if (typeCanBeNull(type)) {
    feConvertValue(type, tDynamic, source.token);
    var checked = result;
    if (type == tDynamic) checked = tObject;
    feOperand(opTypeCast, checked);
    if (checked != result) feConvertValue(checked, result, expression.token);
  }
  if (source.kind == astName && source.binding >= 0)
    feFlow.types[source.binding] = result;
  if (result == tNever) flowUnreachable(feFlow);
  return result;
}

int feLowerExpression(AstExpression expression) {
  var type = feLowerValue(expression);
  if (type == tNever) flowUnreachable(feFlow);
  return type;
}

int feLowerValue(AstExpression expression) {
  expression = feWithReceiver(expression);
  var kind = expression.kind;
  if ((kind == astName || kind == astMember) &&
      expression.typeArguments.length != 0)
    feAstError(expression.token, 'type application values are unsupported');
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
    var binding = expression.binding;
    if (binding >= 0) {
      return feReadLocal(binding, expression.token);
    }
    var symbol = feExpressionSymbol(expression, false);
    if (symbol < 0)
      feAstError(expression.token, 'unknown name ' + expression.text);
    return feLoadDeclaration(symbol, expression.token);
  }
  if (kind == astInterpolation) return feLowerInterpolation(expression);
  if (kind == astList) {
    if (expression.constant) return feLowerHint(expression, -1);
    return feLowerList(expression, -1);
  }
  if (kind == astMember) return feLowerMember(expression);
  if (kind == astCall) return feLowerCall(expression, -1);
  if (kind == astIndex) {
    var receiver = feNonNullableValue(
      feLowerExpression(expression.children[0]),
      expression.children[0].token,
    );
    if (receiver == tNever) {
      feLowerInContext(expression.children[1], tDynamic);
      feEmit(opPop);
      return tNever;
    }
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
  if (kind == astPostfix && expression.text == '!')
    return feLowerNullAssertion(expression, -1);
  if (kind == astAssignment || kind == astPostfix) {
    return feLowerAssignment(expression, kind == astPostfix);
  }
  if (kind == astTypeTest || kind == astTypeCast) {
    var actual = feLowerExpression(expression.children[0]);
    if (kind == astTypeCast && actual == tVoid)
      feBuiltinTyped(bBoxRef, 1, tDynamic);
    else
      feConvertValue(actual, tDynamic, expression.children[0].token);
    var target = resolveType(feSymbols, expression.typeArguments[0]);
    if (kind == astTypeCast) {
      feOperand(opTypeCast, target);
      var binding = expression.children[0].binding;
      if (binding >= 0) {
        if (actual == tVoid && !typeIsSubtype(actual, target))
          feFlow.types[binding] = target;
        else
          flowPromote(feFlow, binding, target);
      }
      return target;
    }
    feOperand(opTypeTest, target);
    if (expression.text == 'is!') feEmit(opNot);
    return tBool;
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
    var result = typingUnary(op, type);
    if (result < 0) feAstError(expression.token, 'invalid unary operand type');
    if (result == tNever) return tNever;
    if (type == tNum || type == tDynamic) {
      var value = feTemp(type);
      feOperand(opStoreLocal, value);
      if (op == '-')
        feInteger(0, tInt);
      else
        feInteger(-1, tInt);
      feConvertValue(tInt, tDynamic, expression.token);
      feOperand(opLoadLocal, value);
      var builtin = bValueSub;
      if (op == '~') builtin = bValueXor;
      feBuiltinTyped(builtin, 2, result);
      return result;
    }
    var operation = opNeg;
    if (op == '~') operation = opBitNot;
    feEmit(operation);
    return result;
  }
  if (kind == astBinary) {
    var op = expression.text;
    if (op == '??') return feLowerCoalescing(expression, -1);
    if (op == '&&' || op == '||') {
      feFlow = flowSplit(feFlow);
      var otherwise = <int>[];
      var falseFlow = feConditionJumps(expression, false, otherwise);
      feInteger(1, tBool);
      var done = feJump(opJump);
      fePatchJumps(otherwise, ir.length);
      feInteger(0, tBool);
      fePatch(done, ir.length);
      feFlow = flowUnsplit(feJoinFlow(feFlow, falseFlow));
      return tBool;
    }
    var left = feLowerExpression(expression.children[0]);
    var right = feLowerExpression(expression.children[1]);
    return feCombine(op, left, right, expression.token);
  }
  if (kind == astConditional) return feLowerConditional(expression, -1);
  feAstError(expression.token, 'unsupported expression');
}

int feLowerCoalescing(AstExpression expression, int context) {
  var source = expression.children[0];
  var left = feLowerHint(source, context);
  if (left == tVoid)
    feAstError(source.token, 'void expression cannot be used as a value');
  feFlow = flowSplit(feFlow);
  if (left == tNull) {
    feEmit(opPop);
    var type = feLowerHint(expression.children[1], context);
    feFlow = flowUnsplit(feFlow);
    return type;
  }
  var value = feTemp(left);
  feOperand(opStoreLocal, value);
  if (typeCanBeNull(left)) {
    // Nullable references and tagged values both encode null as zero.
    feOperand(opLoadLocal, value);
    feInteger(0, tNull);
    feEmit(opNe);
  } else {
    feInteger(1, tBool);
  }
  var present = feJump(opJumpTrue);
  var afterLeft = feFlow;
  feFlow = flowCopy(afterLeft);
  if (source.kind == astName && source.binding >= 0)
    flowNull(feFlow, source.binding, true);
  else if (!typeCanBeNull(left))
    flowUnreachable(feFlow);
  var right = feLowerHint(expression.children[1], context);
  var result = typingCoalescing(left, right);
  feConvertValue(right, result, expression.children[1].token);
  var rightFlow = feFlow;
  var done = feJump(opJump);
  fePatch(present, ir.length);
  feFlow = afterLeft;
  if (source.kind == astName && source.binding >= 0)
    flowNull(feFlow, source.binding, false);
  feOperand(opLoadLocal, value);
  var promoted = typeNonNullable(left);
  feNarrowValue(left, promoted);
  feConvertValue(promoted, result, source.token);
  feFlow = flowUnsplit(feJoinFlow(feFlow, rightFlow));
  fePatch(done, ir.length);
  return result;
}

int feLowerConditional(AstExpression expression, int context) {
  feFlow = flowSplit(feFlow);
  var otherwise = <int>[];
  var falseFlow = feConditionJumps(expression.children[0], false, otherwise);
  var type = feLowerHint(expression.children[1], context);
  var trueFlow = feFlow;
  var thenValue = feTemp(type);
  feOperand(opStoreLocal, thenValue);
  var thenConvert = feJump(opJump);
  fePatchJumps(otherwise, ir.length);
  feFlow = falseFlow;
  var elseType = feLowerHint(expression.children[2], context);
  feFlow = feJoinFlow(trueFlow, feFlow);
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
  feFlow = flowUnsplit(feFlow);
  return result;
}

void feLowerVariable(AstVariable variable) {
  feAt = variable.token;
  feCheckMetadata(variable.metadata, feOwners[feFunction]);
  var type = -1;
  if (variable.type.name != '') type = resolveType(feSymbols, variable.type);
  if (type < 0 && variable.initializer.isEmpty) type = tDynamic;
  var value = type;
  ConstantValue? constant;
  if (variable.modifier == 'const') {
    feConstants.localTypes = feFlow.types;
    if (variable.initializer.isEmpty)
      feAstError(variable.token, 'constant requires an initializer');
    constant = evaluateConstant(
      feConstants,
      variable.initializer[0],
      type,
      true,
    );
    value = constant.type;
    feConstantValue(constant, value, variable.token);
  } else if (variable.initializer.length != 0)
    value = feLowerHint(variable.initializer[0], type);
  else
    feInteger(0, type);
  if (type < 0) {
    if (value == tNull) value = feConvertValue(value, tDynamic, variable.token);
    type = value;
  }
  feConvertValue(value, type, variable.token);
  var slot = feTemp(type);
  feBindLocal(variable.binding, type, slot);
  flowDeclare(
    feFlow,
    variable.binding,
    type,
    typeCanBeNull(type) &&
        !feBindings.variables[variable.binding].finalVariable,
  );
  if (variable.initializer.isNotEmpty)
    flowWrite(feFlow, variable.binding, type, value);
  if (constant != null) {
    if (feConstants.locals.isEmpty) {
      var unknown = ConstantValue(-1, tNull, 0, '');
      while (feConstants.locals.length < feBindings.variables.length)
        feConstants.locals.add(unknown);
    }
    feConstants.locals[variable.binding] = constantWithType(constant, type);
  }
  feOperand(opStoreLocal, slot);
}

void feLoopEnd(int breakBase, int continueBase, int end, int repeat) {
  while (feBreaks.length > breakBase) {
    fePatch(feBreaks.removeLast(), end);
    feFlow = feJoinFlow(feFlow, feBreakFlows.removeLast());
  }
  while (feContinues.length > continueBase) {
    fePatch(feContinues.removeLast(), repeat);
    feContinueFlows.removeLast();
  }
  feLoopBreaks.removeLast();
  feLoopContinues.removeLast();
}

void feContinueFlow(int token, int base) {
  var i = base;
  while (i < feContinueFlows.length) {
    feFlow = feJoinFlow(feFlow, feContinueFlows[i]);
    i++;
  }
  i = 0;
  while (i < feLabels.length) {
    var label = feLabels[i];
    if (label.target == token) {
      var j = 0;
      while (j < label.continueFlows.length) {
        feFlow = feJoinFlow(feFlow, label.continueFlows[j]);
        j++;
      }
    }
    i++;
  }
}

void feLoopFlow(AstStatement statement) {
  var written = <int>[];
  var seen = List<bool>.filled(feBindingTypes.length, false);
  var body = 0;
  if (statement.kind == astForStatement) body = 1;
  collectWrittenStatement(statement.children[body], seen, written);
  var i = 0;
  while (i < statement.condition.length) {
    collectWrittenExpression(statement.condition[i], seen, written);
    i++;
  }
  i = 0;
  while (i < statement.update.length) {
    collectWrittenExpression(statement.update[i], seen, written);
    i++;
  }
  flowDemote(feFlow, written, feBindingTypes);
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
    var i = 0;
    while (i < statement.children.length) {
      feLowerStatement(statement.children[i]);
      i++;
    }
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
    flowUnreachable(feFlow);
    return;
  }
  if (kind == astIfStatement) {
    feFlow = flowSplit(feFlow);
    var otherwise = <int>[];
    var falseFlow = feConditionJumps(statement.condition[0], false, otherwise);
    feLowerStatement(statement.children[0]);
    var trueFlow = feFlow;
    if (statement.children.length == 2) {
      var done = feJump(opJump);
      fePatchJumps(otherwise, ir.length);
      feFlow = falseFlow;
      feLowerStatement(statement.children[1]);
      fePatch(done, ir.length);
    } else {
      fePatchJumps(otherwise, ir.length);
      feFlow = falseFlow;
    }
    feFlow = flowUnsplit(feJoinFlow(trueFlow, feFlow));
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
    if (kind == astForStatement) feLowerStatement(statement.children[0]);
    feFlow = flowSplit(feFlow);
    feLoopFlow(statement);
    var repeat = ir.length;
    var exit = <int>[];
    var exitFlow = flowCopy(feFlow);
    flowUnreachable(exitFlow);
    if (statement.condition.length != 0)
      exitFlow = feConditionJumps(statement.condition[0], false, exit);
    var breakBase = feBreaks.length;
    var continueBase = feContinues.length;
    feLoopBreaks.add(breakBase);
    feLoopContinues.add(continueBase);
    if (kind == astForStatement)
      feLowerStatement(statement.children[1]);
    else
      feLowerStatement(statement.children[0]);
    var update = ir.length;
    feContinueFlow(statement.token, continueBase);
    var updateIndex = 0;
    while (updateIndex < statement.update.length) {
      feLowerExpression(statement.update[updateIndex]);
      feEmit(opPop);
      updateIndex++;
    }
    feOperand(opJump, repeat);
    fePatchJumps(exit, ir.length);
    feLabelRepeat(statement.token, update);
    feFlow = exitFlow;
    feLoopEnd(breakBase, continueBase, ir.length, update);
    feFlow = flowUnsplit(feFlow);
    return;
  }
  if (kind == astBreakStatement) {
    if (statement.expressions.isNotEmpty) {
      feLowerLabeledJump(statement, false);
      return;
    }
    if (feLoopBreaks.isEmpty) feError('break outside loop');
    feBreaks.add(feJump(opJump));
    feBreakFlows.add(flowCopy(feFlow));
    flowUnreachable(feFlow);
    return;
  }
  if (kind == astContinueStatement) {
    if (statement.expressions.isNotEmpty) {
      feLowerLabeledJump(statement, true);
      return;
    }
    if (feLoopContinues.isEmpty) feError('continue outside loop');
    feContinues.add(feJump(opJump));
    feContinueFlows.add(flowCopy(feFlow));
    flowUnreachable(feFlow);
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
    if (imageKind == 0 &&
        feRawGlobals[i] == 0 &&
        feGlobalNodes[i].modifier != 'const') {
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
  var previousFlow = feFlow;
  ir = <int>[];
  irTypes = <int>[];
  feSlotTypes = <int>[];
  feNextLocal = 0;
  feInitializingGlobal = global;
  feFlow = flowCreate(0);
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
  feFlow = previousFlow;
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
      if (word == 1 && (op == opJump || op == opJumpFalse || op == opJumpTrue))
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
  feMembers.clear();
  feMemberFunctions.clear();
  feClassFieldStarts.clear();
  feFieldNodes.clear();
  feClassFieldCounts.clear();
  feClassConstructors.clear();
  feFieldTypes.clear();
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
  feParamTypes.clear();
  feParamDefaults.clear();
  feConstantObjects.clear();
  feConstantGetters.clear();
  constantLists.clear();
  feBindings = FunctionBindings(<LocalVariable>[], -1);
  feBindingTypes = <int>[];
  feBindingSlots = <int>[];
  feFlow = flowCreate(0);
  feBreaks.clear();
  feContinues.clear();
  feBreakFlows.clear();
  feContinueFlows.clear();
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
  entryFunction = -1;
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
  checkInitializers(feSymbols, syntax);
  feConstants = ConstantContext(feSymbols, feGlobalNodes, globalTypes);
  feConstants.identical = symbolOwnDeclaration(
    feSymbols,
    sourceCore,
    'identical',
  );
  feCheckUnitMetadata(syntax);
  var constant = 0;
  while (constant < feGlobalNodes.length) {
    if (feGlobalNodes[constant].modifier == 'const') {
      var value = evaluateGlobalConstant(feConstants, constant);
      globalTypes[constant] = value.type;
      if (value.type == value.kind &&
          (value.kind == tInt ||
              value.kind == tBool ||
              value.kind == tString)) {
        _feLiteralTypes[constant] = value.kind;
        _feLiteralValues[constant] = value.integer;
        if (value.kind == tString)
          _feLiteralValues[constant] = internString(value.text);
      }
    }
    constant++;
  }
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
  var bodyBindings = <FunctionBindings>[];
  var bindingFunction = 0;
  while (bindingFunction < sourceFunctions) {
    bodyBindings.add(
      bindFunctionLocals(
        source,
        feFunctionNodes[bindingFunction],
        feOwners[bindingFunction] >= 0,
      ),
    );
    bindingFunction++;
  }
  feResolveDefaults(sourceFunctions);
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
    if (feGlobalInitializers[i].getter < 0 &&
        feGlobalNodes[i].modifier != 'const') {
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
    feBindings = bodyBindings[f];
    feConstants.locals.clear();
    feFlow = flowCreate(feBindings.variables.length);
    feBindingTypes = <int>[];
    feBindingSlots = <int>[];
    var binding = 0;
    while (binding < feBindings.variables.length) {
      feBindingTypes.add(-1);
      feBindingSlots.add(-1);
      binding++;
    }
    feSlotTypes = <int>[];
    feNextLocal = 0;
    var start = feParamStarts[f];
    var p = 0;
    while (p < functions[f].parameters) {
      var slot = feTemp(feParamTypes[start + p]);
      var binding = feBindings.receiver;
      var parameter = p;
      if (feOwners[f] >= 0) parameter--;
      if (parameter >= 0)
        binding = functionSyntax.parameters[parameter].binding;
      if (binding >= 0) feBindLocal(binding, feParamTypes[start + p], slot);
      p++;
    }
    if (feConstructors[f] == 1) {
      var bindings = feBindings;
      feBindings = FunctionBindings(<LocalVariable>[], -1);
      var owner = feOwners[f];
      var field = feClassFieldStarts[owner];
      var end = field + feClassFieldCounts[owner];
      while (field < end) {
        if (feFieldNodes[field].initializer.length != 0) {
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
      feBindings = bindings;
      p = 1;
      while (p < functions[f].parameters) {
        var field = feParamFields[start + p];
        if (field >= 0) {
          feOperand(opLoadLocal, 0);
          feOperand(opInt, feFieldIndices[field]);
          feOperand(opLoadLocal, p);
          var syntax = functionSyntax.parameters[p - 1];
          var fieldType = feFieldTypes[field];
          feConvertValue(feParamTypes[start + p], fieldType, syntax.token);
          feBuiltinTyped(bObjectSet, 3, fieldType);
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
      var result = functions[f].result;
      if (feFlow.reachable && !typeCanBeNull(result)) {
        feAstError(
          functionSyntax.token,
          'non-nullable function may complete without returning',
        );
      }
      if (typeCanBeNull(result)) {
        feInteger(0, tNull);
        feConvertValue(tNull, result, functionSyntax.token);
      } else {
        feInteger(0, result);
      }
      feEmit(opReturn);
    }
    functions[f].locals = feNextLocal;
    functions[f].localTypes = feSlotTypes;
    f++;
  }
  feGenerateGlobals(sourceGlobals);
  if (imageKind == 0)
    feGenerateEntry();
  else
    feGenerateConstantObjects();
}

void feGenerateEntry() {
  var symbol = symbolExportedDeclaration(feSymbols, entrySource, 'main');
  if (symbol < 0 || feSymbols.declarations[symbol].kind != symbolFunction) {
    sourceError(
      feSources,
      feSources.files[entrySource].tokens[0],
      'entry library must expose a main function',
    );
  }
  var main = feSymbols.declarations[symbol].target;
  var syntax = feFunctionNodes[main];
  if (syntax.getter) feAstError(syntax.token, 'main must be a function');
  var parameters = syntax.parameters;
  var positional = 0;
  var required = 0;
  var p = 0;
  while (p < parameters.length) {
    if (parameters[p].kind != astNamedParameter) {
      positional++;
      if (parameters[p].kind == astRequiredPositional) required++;
    } else if (parameters[p].required)
      feAstError(parameters[p].token, 'main cannot require named arguments');
    p++;
  }
  if (required > 2)
    feAstError(
      syntax.token,
      'main accepts at most two required positional parameters',
    );
  var offset = feParamStarts[main];
  var argumentsType = listType(tString);
  if (positional > 0 && !typingAssignable(argumentsType, feParamTypes[offset]))
    feAstError(
      parameters[0].token,
      'first main parameter must accept List<String>',
    );
  var supplied = positional;
  if (supplied > 2) supplied = 2;
  p = supplied;
  while (p < parameters.length) {
    var value = feParamDefaults[offset + p];
    if (typeIsList(value.kind)) feConstantGetter(value);
    p++;
  }
  feGenerateConstantObjects();
  entryFunction = main;
  if (parameters.length <= 1 && parameters.length == positional) return;
  var types = <int>[];
  if (positional > 0) types.add(argumentsType);
  entryFunction = functions.length;
  functions.add(
    FunctionInfo(
      '#entry',
      ir.length,
      types.length,
      types.length,
      tVoid,
      types,
      <int>[],
      entrySource,
    ),
  );
  feSlotTypes = <int>[];
  feNextLocal = 0;
  if (positional > 0) feTemp(argumentsType);
  p = 0;
  while (p < parameters.length) {
    if (p < supplied) {
      var actual = tNull;
      if (p == 0) {
        feOperand(opLoadLocal, 0);
        actual = argumentsType;
      } else {
        feInteger(0, tNull);
      }
      var expected = feParamTypes[offset + p];
      if (typeIsSubtype(actual, expected)) {
        feConvertValue(actual, expected, parameters[p].token);
      } else {
        feConvertValue(actual, tDynamic, parameters[p].token);
        feBuiltinTyped(bValueCast, 1, expected);
      }
    } else {
      feDefaultArgument(offset + p, syntax.token);
    }
    p++;
  }
  feCall(main, parameters.length);
  feEmit(opPop);
  feInteger(0, tVoid);
  feEmit(opReturn);
  functions[entryFunction].locals = feNextLocal;
  functions[entryFunction].localTypes = feSlotTypes;
}

void feLowerForIn(AstStatement statement) {
  var declaration = statement.variables[0];
  feCheckMetadata(declaration.metadata, feOwners[feFunction]);
  var context = -1;
  if (declaration.type.name != '')
    context = listType(resolveType(feSymbols, declaration.type));
  var iterableType = feNonNullableValue(
    feLowerHint(statement.expressions[0], context),
    statement.expressions[0].token,
  );
  if (!typeIsList(iterableType)) {
    feAstError(statement.token, 'for-in currently requires a List');
  }
  var iterable = feTemp(iterableType);
  feOperand(opStoreLocal, iterable);
  var length = feTemp(tInt);
  feOperand(opLoadLocal, iterable);
  feBuiltin(bListLength, 1);
  feOperand(opStoreLocal, length);
  var index = feTemp(tInt);
  feOperand(opInt, 0);
  feOperand(opStoreLocal, index);
  var element = typeArgument(iterableType);
  var type = element;
  if (context >= 0) type = typeArgument(context);
  if (!typingAssignable(element, type)) {
    feAstError(
      declaration.token,
      'for-in variable type must match the List element type',
    );
  }
  var variable = feTemp(type);
  feBindLocal(declaration.binding, type, variable);
  feFlow = flowSplit(feFlow);
  feLoopFlow(statement);
  var exitFlow = flowCopy(feFlow);
  flowDeclare(feFlow, declaration.binding, type, true);
  var repeat = ir.length;
  feOperand(opLoadLocal, iterable);
  feBuiltin(bListLength, 1);
  feOperand(opLoadLocal, length);
  feEmit(opEq);
  var unchanged = feJump(opJumpTrue);
  feCall(feFindFunction('rtListModificationError'), 0);
  feEmit(opPop);
  fePatch(unchanged, ir.length);
  feOperand(opLoadLocal, index);
  feOperand(opLoadLocal, length);
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
  feContinueFlow(statement.token, continueBase);
  feOperand(opLoadLocal, index);
  feOperand(opInt, 1);
  feEmit(opAdd);
  feOperand(opStoreLocal, index);
  feOperand(opJump, repeat);
  fePatch(done, ir.length);
  feLabelRepeat(statement.token, update);
  feFlow = exitFlow;
  feLoopEnd(breakBase, continueBase, ir.length, update);
  feFlow = flowUnsplit(feFlow);
}

void feLowerDoWhile(AstStatement statement) {
  feFlow = flowSplit(feFlow);
  feLoopFlow(statement);
  var repeat = ir.length;
  var breakBase = feBreaks.length;
  var continueBase = feContinues.length;
  feLoopBreaks.add(breakBase);
  feLoopContinues.add(continueBase);
  feLowerStatement(statement.children[0]);
  var condition = ir.length;
  feContinueFlow(statement.token, continueBase);
  var repeats = <int>[];
  feConditionJumps(statement.condition[0], true, repeats);
  fePatchJumps(repeats, repeat);
  feLabelRepeat(statement.token, condition);
  feLoopEnd(breakBase, continueBase, ir.length, condition);
  feFlow = flowUnsplit(feFlow);
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
  var symbol = feExpressionSymbol(expression, false);
  if (symbol >= 0) {
    var declaration = feSymbols.declarations[symbol];
    return declaration.kind == symbolGlobal &&
        _feLiteralTypes[declaration.target] != 0;
  }
  return false;
}

void feLowerSwitch(AstStatement statement) {
  var type = feLowerExpression(statement.expressions[0]);
  if (type != tInt && type != tString && type != tBool) {
    feAstError(
      statement.token,
      'switch currently requires int, String or bool',
    );
  }
  var value = feTemp(type);
  feOperand(opStoreLocal, value);
  feFlow = flowSplit(feFlow);
  List<int> entries = <int>[];
  var fallback = -1;
  var booleans = 0;
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
      if (type == tBool) {
        var value = -1;
        if (constant.kind == astBoolean) {
          value = 0;
          if (constant.text == 'true') value = 1;
        } else {
          var symbol = feExpressionSymbol(constant, false);
          if (symbol >= 0) {
            var declaration = feSymbols.declarations[symbol];
            if (declaration.kind == symbolGlobal)
              value = _feLiteralValues[declaration.target];
          }
        }
        if (value == 0) booleans = booleans | 1;
        if (value == 1) booleans = booleans | 2;
      }
      feCombine('==', type, caseType, constant.token);
      var next = feJump(opJumpFalse);
      entries.add(feJump(opJump));
      fePatch(next, ir.length);
    }
    i++;
  }
  var unmatched = feJump(opJump);
  var entryFlow = flowCopy(feFlow);
  var exitFlow = flowCopy(feFlow);
  if (fallback >= 0 || booleans == 3) flowUnreachable(exitFlow);
  var breakBase = feBreaks.length;
  feLoopBreaks.add(breakBase);
  i = 0;
  while (i < statement.children.length) {
    var branch = statement.children[i];
    feFlow = flowCopy(entryFlow);
    if (entries[i] >= 0) fePatch(entries[i], ir.length);
    if (i == fallback) fePatch(unmatched, ir.length);
    var child = 0;
    while (child < branch.children.length) {
      feLowerStatement(branch.children[child]);
      child++;
    }
    if (branch.children.isNotEmpty) {
      feBreaks.add(feJump(opJump));
      feBreakFlows.add(flowCopy(feFlow));
    } else if (i + 1 == statement.children.length) {
      exitFlow = feJoinFlow(exitFlow, feFlow);
    }
    i++;
  }
  if (fallback < 0) fePatch(unmatched, ir.length);
  feFlow = exitFlow;
  while (feBreaks.length > breakBase) {
    fePatch(feBreaks.removeLast(), ir.length);
    feFlow = feJoinFlow(feFlow, feBreakFlows.removeLast());
  }
  feLoopBreaks.removeLast();
  feFlow = flowUnsplit(feFlow);
}

void feLabelRepeat(int token, int target) {
  var i = 0;
  while (i < feLabels.length) {
    if (feLabels[i].target == token) feLabels[i].repeat = target;
    i++;
  }
}

void feLowerLabel(AstStatement statement) {
  feFlow = flowSplit(feFlow);
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
    feFlow = feJoinFlow(feFlow, label.breakFlows[i]);
    i++;
  }
  i = 0;
  while (i < label.continues.length) {
    fePatch(label.continues[i], label.repeat);
    i++;
  }
  feLabels.removeLast();
  feFlow = flowUnsplit(feFlow);
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
    label.continueFlows.add(flowCopy(feFlow));
  } else {
    label.breaks.add(feJump(opJump));
    label.breakFlows.add(flowCopy(feFlow));
  }
  flowUnreachable(feFlow);
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
