import 'ast.dart';
import 'frontend/arguments.dart';
import 'frontend/literals.dart';
import 'frontend/parameters.dart';
import 'frontend/patterns.dart';
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
  FunctionBindings bindings;
  List<int> code;
  List<int> types;
  List<int> locals;
  int result;
  int getter;
  int setter;
  int state;

  GlobalInitializer(
    this.bindings,
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

class FeCapture {
  final int binding;
  final int type;
  final int promoted;
  final int assignment;

  FeCapture(this.binding, this.type, this.promoted, this.assignment);
}

class FeClosure {
  final List<FeCapture> captures = <FeCapture>[];
  bool prepared = false;
}

class FeFunctionState {
  final List<int> code = ir;
  final List<int> types = irTypes;
  final int function = feFunction;
  final int token = feAt;
  final FunctionBindings bindings = feBindings;
  final List<int> bindingTypes = feBindingTypes;
  final List<int> bindingSlots = feBindingSlots;
  final List<int> slots = feSlotTypes;
  final int nextLocal = feNextLocal;
  final int implicitReceiverSlot = feImplicitReceiverSlot;
  final FlowState flow = feFlow;
  final List<ConstantValue> constants = feConstants.locals;
  final List<int> constantTypes = feConstants.localTypes;
  final int constantScope = feConstants.lexicalClass;
  final List<int> breaks = feBreaks;
  final List<int> continues = feContinues;
  final List<FlowState> breakFlows = feBreakFlows;
  final List<FlowState> continueFlows = feContinueFlows;
  final List<int> loopBreaks = feLoopBreaks;
  final List<int> loopContinues = feLoopContinues;
  final List<ControlLabel> labels = feLabels;
  final List<int>? returns = feReturnTypes;
  final int initializingGlobal = feInitializingGlobal;

  FeFunctionState();

  void restore() {
    ir = code;
    irTypes = types;
    feFunction = function;
    feAt = token;
    feBindings = bindings;
    feBindingTypes = bindingTypes;
    feBindingSlots = bindingSlots;
    feSlotTypes = slots;
    feNextLocal = nextLocal;
    feImplicitReceiverSlot = implicitReceiverSlot;
    feFlow = flow;
    feConstants.locals = constants;
    feConstants.localTypes = constantTypes;
    feConstants.lexicalClass = constantScope;
    feBreaks = breaks;
    feContinues = continues;
    feBreakFlows = breakFlows;
    feContinueFlows = continueFlows;
    feLoopBreaks = loopBreaks;
    feLoopContinues = loopContinues;
    feLabels = labels;
    feReturnTypes = returns;
    feInitializingGlobal = initializingGlobal;
  }
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
List<LocalFunctionBinding> feLocalFunctions = <LocalFunctionBinding>[];
List<FeClosure> feLocalClosures = <FeClosure>[];
List<List<ConstantValue>?> feLocalConstants = <List<ConstantValue>?>[];
List<int> feLocalOwners = <int>[];
int feLocalStart = 0;
int feImplicitReceiverSlot = -1;
List<bool> feLocalInferred = <bool>[];
List<int> feLocalContexts = <int>[];
List<int>? feReturnTypes;
List<AstClass> feClassNodes = <AstClass>[];
List<ClassMembers> feMembers = <ClassMembers>[];
List<List<int>> feMemberFunctions = <List<int>>[];
List<List<int>> feClassStaticGlobals = <List<int>>[];
List<int> feClassFieldStarts = <int>[];
List<AstVariable> feGlobalNodes = <AstVariable>[];
List<AstVariable> feFieldNodes = <AstVariable>[];
List<FunctionBindings> feFieldBindings = <FunctionBindings>[];
List<int> feClassSources = <int>[];
List<int> feGlobalSources = <int>[];
List<int> feGlobalOwners = <int>[];
List<int> feRawGlobals = <int>[];
List<GlobalInitializer> feGlobalInitializers = <GlobalInitializer>[];
int feRuntimeTokens = 0;
List<int> _feLiteralTypes = <int>[];
List<int> _feLiteralValues = <int>[];
List<List<ConstantValue>> feParamDefaults = <List<ConstantValue>>[];
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
List<List<int>> feClassConstructors = <List<int>>[];
List<ConstructorPlan> feConstructorPlans = <ConstructorPlan>[];
List<int> feFieldTypes = <int>[];
List<int> feFieldIndices = <int>[];
List<int> feOwners = <int>[];
List<int> feConstructors = <int>[];
int fePragmaClass = -1;
int fePragmaNameField = -1;
int fePragmaOptionsField = -1;

Never feError(String message) {
  sourceError(feSources, feTokens[feAt], message);
}

bool feClassType(int type) {
  return typeIsClass(type);
}

int feField(int owner, String name, int token) {
  var index = lookupMember(feMembers[owner], name);
  if (index >= 0 && feMembers[owner].members[index].field >= 0)
    return feClassFieldStarts[owner] + feMembers[owner].members[index].field;
  feAstError(token, 'unknown instance field ' + classNames[owner] + '.' + name);
}

int feMethod(int owner, String name, bool getter) {
  var index = lookupMember(feMembers[owner], name);
  if (index < 0) return -1;
  var member = feMembers[owner].members[index];
  if (member.isStatic) return -1;
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

int feRegisterFunction(
  AstFunction syntax,
  int owner,
  bool constructor, [
  bool local = false,
]) {
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
    var symbol = symbolOwnDeclaration(feSymbols, source, syntax.name);
    feSymbols.declarations[symbol].kind = symbolBuiltin;
    feSymbols.declarations[symbol].target = primitive;
    return -1;
  }
  var id = functions.length;
  var types = <int>[];
  var source = feTokens[syntax.token].source;
  var name = syntax.name;
  var result = tDynamic;
  if (constructor)
    result = classType(owner);
  else if (syntax.result.name != '')
    result = resolveType(feSymbols, syntax.result);
  else if (owner >= 0 &&
      !syntax.isStatic &&
      syntax.name == 'toString' &&
      !syntax.getter &&
      !syntax.setter)
    result = tString;
  if (owner >= 0) {
    if (!constructor) name = classNames[owner] + '.' + syntax.name;
    if (!syntax.isStatic) {
      types.add(classType(owner));
    }
  }
  var p = 0;
  while (p < syntax.parameters.length) {
    var parameter = syntax.parameters[p];
    var type = tDynamic;
    if (parameter.fieldFormal) {
      if (!constructor)
        feAstError(
          parameter.token,
          'field-formal parameter requires a constructor',
        );
      var entry = feField(owner, parameter.name, parameter.token);
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
    } else if (parameter.type.name != '') {
      type = resolveType(feSymbols, parameter.type);
    }
    types.add(type);
    p++;
  }
  var count = types.length;
  functions.add(
    FunctionInfo(name, 0, count, count, result, types, <int>[], source),
  );
  feParamDefaults.add(<ConstantValue>[]);
  feFunctionNodes.add(syntax);
  feOwners.add(owner);
  if (constructor) {
    feConstructors.add(1);
    feClassConstructors[owner].add(id);
  } else {
    feConstructors.add(0);
  }
  if (owner < 0 && !local) {
    var symbol = symbolOwnDeclaration(feSymbols, source, syntax.name);
    if (syntax.setter)
      feSymbols.declarations[symbol].setter = id;
    else
      feSymbols.declarations[symbol].target = id;
  }
  var callable = !constructor && !syntax.getter && !syntax.setter;
  p = 0;
  while (p < syntax.parameters.length) {
    if (syntax.parameters[p].kind != astRequiredPositional) callable = false;
    p++;
  }
  functions[id].callableShape = callable;
  if (callable && owner >= 0 && !syntax.isStatic)
    functions[id].closureLayout = ClosureLayout(<int>[classType(owner)], true);
  return id;
}

bool feIsNativeInt64(AstType syntax) {
  var symbol = feTypeSymbol(syntax);
  return symbol >= 0 &&
      feSymbols.declarations[symbol].source == sourceFfi &&
      feSymbols.declarations[symbol].name == 'Int64';
}

void feCheckNativeInt64(AstType syntax) {
  if (!feIsNativeInt64(syntax)) {
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
    feClassConstructors.add(<int>[]);
    feClassStaticGlobals.add(const <int>[]);
    classSizes.add(objectHeaderBytes);
    classPointerMasks.add(<int>[]);
    classTaggedMasks.add(<int>[]);
    classToStringFunctions.add(-1);
    feDeclare(source, syntax.name, symbolClass, owner, syntax.token);
    i++;
  }
  i = 0;
  while (i < unit.variables.length) {
    var syntax = unit.variables[i];
    var symbol = feDeclare(
      feTokens[syntax.token].source,
      syntax.name,
      symbolGlobal,
      -1,
      syntax.token,
    );
    feSymbols.declarations[symbol].writable =
        syntax.modifier != 'final' && syntax.modifier != 'const';
    i++;
  }
  i = 0;
  while (i < unit.functions.length) {
    var syntax = unit.functions[i];
    var source = feTokens[syntax.token].source;
    if (syntax.getter || syntax.setter) {
      if (declareAccessor(feSymbols, source, syntax.name, -1, syntax.setter) <
          0)
        feAstError(syntax.token, 'duplicate declaration ' + syntax.name);
    } else {
      feDeclare(source, syntax.name, symbolFunction, -1, syntax.token);
    }
    i++;
  }
  i = 0;
  while (i < unit.typedefs.length) {
    var syntax = unit.typedefs[i];
    var signature = syntax.type.function;
    if (!sourceVersionAtLeast(
          feSources,
          feTokens[syntax.token].source,
          2,
          13,
        ) &&
        (signature == null || syntax.type.name.endsWith('?')))
      feAstError(
        syntax.token,
        'non-function type aliases require language version 2.13',
      );
    var kind = symbolAlias;
    var target = feSymbols.aliases.length;
    if (syntax.typeParameters.isEmpty &&
        signature != null &&
        feIsNativeInt64(signature.result)) {
      var p = 0;
      while (p < signature.parameters.length) {
        var parameter = signature.parameters[p];
        if (parameter.kind != astRequiredPositional)
          feAstError(
            parameter.token,
            'FFI callbacks require positional parameters',
          );
        feCheckNativeInt64(parameter.type);
        p++;
      }
      if (p > 8)
        feAstError(
          syntax.token,
          'FFI callbacks support up to eight Int64 parameters',
        );
      kind = symbolNativeType;
      target = feNativeNames.length;
      feNativeNames.add(syntax.name);
      feNativeParams.add(p);
    } else {
      var alias = TypeAlias(syntax.type);
      alias.syntaxParameters = syntax.typeParameters;
      feSymbols.aliases.add(alias);
    }
    feDeclare(
      feTokens[syntax.token].source,
      syntax.name,
      kind,
      target,
      syntax.token,
    );
    i++;
  }
  resolveTypeAliasDeclarations(feSymbols);
  for (var alias in feSymbols.aliases) {
    var signature = alias.syntax.function;
    if (alias.parameters.isNotEmpty &&
        signature != null &&
        typeParameterInScope(alias.parameters, signature.result.name) < 0 &&
        feIsNativeInt64(signature.result))
      feAstError(
        alias.syntax.token,
        'generic FFI function aliases are not supported',
      );
  }
  var object = symbolOwnDeclaration(feSymbols, sourceCore, 'Object');
  var objectMembers = feSymbols.declarations[object].instanceMembers;
  i = 0;
  while (i < unit.classes.length) {
    feClassFieldStarts.add(feFieldTypes.length);
    feMembers.add(bindClassMembers(feSources, unit.classes[i], objectMembers));
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
    feRegisterGlobal(unit.variables[i], -1);
    i++;
  }
  i = 0;
  while (i < unit.classes.length) {
    var fields = unit.classes[i].staticFields;
    if (fields.isNotEmpty) feClassStaticGlobals[i] = <int>[];
    var field = 0;
    while (field < fields.length) {
      feClassStaticGlobals[i].add(feRegisterGlobal(fields[field], i));
      field++;
    }
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
          null,
          null,
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

int feRegisterGlobal(AstVariable syntax, int owner) {
  var source = feTokens[syntax.token].source;
  var type = -1;
  if (syntax.type.name != '') type = resolveType(feSymbols, syntax.type);
  if (type < 0 && syntax.initializer.isEmpty) type = tDynamic;
  var global = globalNames.length;
  var name = syntax.name;
  if (owner >= 0) name = classNames[owner] + '.' + name;
  globalNames.add(name);
  globalTypes.add(type);
  feGlobalSources.add(source);
  feGlobalOwners.add(owner);
  feGlobalNodes.add(syntax);
  if (owner < 0 && feRuntimeTokens > 0 && source == 0)
    feRawGlobals.add(1);
  else
    feRawGlobals.add(0);
  _feLiteralTypes.add(0);
  _feLiteralValues.add(0);
  if (owner < 0) {
    var symbol = symbolOwnDeclaration(feSymbols, source, syntax.name);
    feSymbols.declarations[symbol].target = global;
  }
  return global;
}

bool feHasReceiver(int function) {
  return feOwners[function] >= 0 && !feFunctionNodes[function].isStatic;
}

int feParameterOffset(int function) {
  return feHasReceiver(function) || functions[function].closureLayout != null
      ? 1
      : 0;
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
  if (op == opClosureDescriptor || op == opCaptureCellDescriptor)
    irTypes[position] = tPointer;
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
  if (id == bFunctionEntry || id == bFunctionType) return tPointer;
  if (id == bFunctionInvoke) return tDynamic;
  if (id == bHostExit || id == bHostFinish) return tNever;
  if (id == bHostReadIfExists) return nullableType(tString);
  if (id == bIntToString ||
      id == bStringConcat ||
      id == bStringSubstring ||
      id == bStringFromCodes ||
      id == bHostRead ||
      id == bHostCurrentDirectory ||
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

bool feCellBinding(int binding) {
  var variable = bindingDeclaration(feBindings, binding);
  return variable.captured && variable.written && !variable.constant;
}

bool fePromotable(int binding) {
  return !bindingDeclaration(feBindings, binding).writeCaptured;
}

void feAllocateCell(int type) {
  var value = feTemp(type);
  feOperand(opStoreLocal, value);
  feOperand(opCaptureCellDescriptor, type);
  feBuiltinTyped(bObjectNew, 1, tObject);
  var cell = feTemp(tObject);
  feOperand(opStoreLocal, cell);
  feOperand(opLoadLocal, cell);
  feOperand(opInt, 0);
  feOperand(opLoadLocal, value);
  feBuiltinTyped(bObjectSet, 3, type);
  feEmit(opPop);
  feOperand(opLoadLocal, cell);
}

int feLoadLocalStorage(int binding) {
  var slot = feBindingSlots[binding];
  feOperand(opLoadLocal, slot);
  if (feCellBinding(binding)) {
    feOperand(opInt, 0);
    feBuiltinTyped(bObjectGet, 2, feBindingTypes[binding]);
    return feBindingTypes[binding];
  }
  return feSlotTypes[slot];
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
  var variable = feBindings.variables[binding];
  if (variable.function >= 0 &&
      functions[feLocalStart + variable.function].closureLayout == null)
    return feFunctionReference(feLocalStart + variable.function, token);
  if (variable.outer >= 0 && variable.constant) {
    var value = feConstants.locals[binding];
    feConstantValue(value, value.type, token);
    var type = feFlow.types[binding];
    feNarrowValue(value.type, type);
    return type;
  }
  feLocalSlot(binding, token);
  if (feFlow.assignments[binding] != flowAssigned) {
    feAstError(
      token,
      'local is not definitely assigned: ' + feBindings.variables[binding].name,
    );
  }
  var stored = feLoadLocalStorage(binding);
  var type = feFlow.types[binding];
  feNarrowValue(stored, type);
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

int feLexicalOwner(int function) {
  if (feInitializingGlobal >= 0) return feGlobalOwners[feInitializingGlobal];
  if (function >= feLocalStart &&
      function < feLocalStart + feLocalFunctions.length)
    return feLocalOwners[function - feLocalStart];
  return feOwners[function];
}

bool feImplicitMember(AstExpression expression) {
  if (expression.binding >= 0) return false;
  var owner = feLexicalOwner(feFunction);
  if (owner < 0 || lookupMember(feMembers[owner], expression.text) < 0)
    return false;
  var member =
      feMembers[owner].members[lookupMember(feMembers[owner], expression.text)];
  if (!member.isStatic && feBindings.receiver < 0)
    feAstError(expression.token, 'capturing this is not supported');
  return true;
}

int feConstructorType(int symbol, List<AstType> arguments, int token) {
  if (symbol < 0) return -1;
  var declaration = feSymbols.declarations[symbol];
  if (declaration.kind != symbolClass && declaration.kind != symbolAlias)
    return -1;
  var type = resolveDeclarationType(
    feSymbols,
    symbol,
    arguments,
    token,
    const <int>[],
    false,
  );
  if (declaration.kind == symbolAlias &&
      feSymbols.aliases[declaration.target].expandsToParameter)
    feAstError(token, 'type parameter alias has no constructor namespace');
  return type;
}

AstExpression feWithReceiver(AstExpression expression) {
  if (expression.kind != astName || !feImplicitMember(expression))
    return expression;
  var owner = feLexicalOwner(feFunction);
  if (feMembers[owner]
      .members[lookupMember(feMembers[owner], expression.text)]
      .isStatic)
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
  var source = sourceLibrary(feSources, feTokens[token].source);
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

int feStaticOwner(AstExpression expression) {
  if (expression.kind == astName && expression.binding < 0) {
    var owner = feLexicalOwner(feFunction);
    if (owner >= 0) {
      var index = lookupMember(feMembers[owner], expression.text);
      if (index >= 0 && feMembers[owner].members[index].isStatic) return owner;
    }
  } else if (expression.kind == astMember) {
    var receiver = expression.children[0];
    var symbol = feExpressionSymbol(receiver, false);
    var owner = declarationClassOwner(feSymbols, symbol);
    if (owner >= 0) {
      var index = lookupMember(feMembers[owner], expression.text);
      if (receiver.typeArguments.isNotEmpty &&
          index >= 0 &&
          feMembers[owner].members[index].isStatic)
        feAstError(
          receiver.token,
          'static member qualifier does not accept type arguments',
        );
      return owner;
    }
  }
  return -1;
}

MemberBinding feStaticBinding(int owner, String name, int token) {
  feCheckPrivate(owner, name, token);
  var index = lookupMember(feMembers[owner], name);
  if (index < 0) feAstError(token, 'unknown static member ' + name);
  var member = feMembers[owner].members[index];
  if (!member.isStatic)
    feAstError(token, 'instance member requires a receiver');
  return member;
}

int feStaticReadType(int owner, MemberBinding member, int token) {
  if (member.getter >= 0)
    return functions[feMemberFunctions[owner][member.getter]].result;
  if (member.staticField >= 0)
    return feGlobalType(feClassStaticGlobals[owner][member.staticField]);
  feAstError(token, 'member has no getter: ' + member.name);
}

int feReadStaticMember(int owner, MemberBinding member, int token) {
  if (member.method >= 0)
    return feFunctionReference(feMemberFunctions[owner][member.method], token);
  var type = feStaticReadType(owner, member, token);
  if (member.getter >= 0)
    feCall(feMemberFunctions[owner][member.getter], 0);
  else
    feLoadGlobalValue(feClassStaticGlobals[owner][member.staticField]);
  return type;
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
  if (declaration.kind == symbolFunction)
    return feFunctionReference(declaration.target, token);
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

int feCallableType(int function, int token) {
  if (imageKind != 0)
    feAstError(token, 'library output cannot use Dart function values');
  var type = functionValueType(function);
  if (type < 0)
    feAstError(token, 'function values require required positional parameters');
  if (functions[function].callableAdapter == -1)
    functions[function].callableAdapter = -2;
  return type;
}

int feFunctionReference(int function, int token) {
  var type = feCallableType(function, token);
  feOperand(opFunctionReference, function);
  irTypes[ir.length - 2] = type;
  return type;
}

void feCheckPrivate(int owner, String name, int token) {
  if (name.startsWith('_') &&
      sourceLibrary(feSources, feTokens[token].source) !=
          sourceLibrary(feSources, feClassSources[owner])) {
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
  declareObjectType(feSymbols, tObject);
  declareSymbol(feSymbols, sourceCore, 'Null', symbolType, tNull);
  declareSymbol(feSymbols, sourceCore, 'Never', symbolType, tNever);
  declareSymbol(feSymbols, sourceCore, 'Function', symbolType, tFunction);
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
  declareSymbol(
    feSymbols,
    sourceHost,
    'hostReadIfExists',
    symbolBuiltin,
    bHostReadIfExists,
  );
  declareSymbol(
    feSymbols,
    sourceHost,
    'hostCurrentDirectory',
    symbolBuiltin,
    bHostCurrentDirectory,
  );
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

int feBinaryOp(String op) => switch (op) {
  '+' => opAdd,
  '-' => opSub,
  '*' => opMul,
  '~/' => opDiv,
  '%' => opMod,
  '&' => opAnd,
  '|' => opOr,
  '^' => opXor,
  '<<' => opShl,
  '>>' => opShr,
  '>>>' => opUshr,
  '==' => opEq,
  '!=' => opNe,
  '<' => opLt,
  '<=' => opLe,
  '>' => opGt,
  '>=' => opGe,
  _ => feError('unsupported operator ' + op),
};

int feValueOperation(String op) => switch (op) {
  '+' => bValueAdd,
  '-' => bValueSub,
  '*' => bValueMul,
  '~/' => bValueDiv,
  '%' => bValueMod,
  '&' => bValueAnd,
  '|' => bValueOr,
  '^' => bValueXor,
  '<<' => bValueShl,
  '>>' => bValueShr,
  '>>>' => bValueUshr,
  '==' || '!=' => bValueEq,
  '<' => bValueLt,
  '<=' => bValueLe,
  '>' => bValueGt,
  _ => bValueGe,
};

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
      equal && (left != right || typeIsFunction(left) || left == tFunction)) {
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
    if (binding < 0 || !fePromotable(binding)) return;
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
    if (binding >= 0 && fePromotable(binding)) {
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
  if (expression.kind == astSwitchExpression)
    return feLowerSwitchExpression(expression, context);
  if (expression.kind == astNullAware)
    return feLowerNullAware(expression, context);
  if (expression.kind == astCascade) return feLowerCascade(expression, context);
  if (expression.kind == astFunctionExpression)
    return feLowerFunctionExpression(expression, context);
  if (expression.kind == astPostfix && expression.text == '!')
    return feLowerNullAssertion(expression, context);
  if ((expression.kind == astList || expression.kind == astCall) &&
      expression.constant) {
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
    feLowerAssignedValue(expression, context),
    context,
    expression.token,
  );
}

int feImplicitCall(int actual, int expected, int token) {
  if (expected < 0 || !feClassType(actual)) return actual;
  var target = typeNonNullable(expected);
  if (!typeIsFunction(target) && target != tFunction) return actual;
  var method = feMethod(typeArgument(actual), 'call', false);
  if (method < 0) return actual;
  return feCreateBoundMethod(method, token);
}

int feLowerAssignedValue(AstExpression expression, int context) {
  // Coerce the whole expression; context alone does not coerce its operands.
  return feImplicitCall(
    feLowerHint(expression, context),
    context,
    expression.token,
  );
}

void feResolvePragma() {
  fePragmaClass = -1;
  fePragmaNameField = -1;
  fePragmaOptionsField = -1;
  var symbol = symbolExportedDeclaration(feSymbols, sourceCore, 'pragma');
  if (symbol < 0 || feSymbols.declarations[symbol].kind != symbolClass) return;
  fePragmaClass = feSymbols.declarations[symbol].target;
  var members = feMembers[fePragmaClass];
  var name = lookupMember(members, 'name');
  var options = lookupMember(members, 'options');
  if (name >= 0) fePragmaNameField = members.members[name].field;
  if (options >= 0) fePragmaOptionsField = members.members[options].field;
}

int fePragmaFlags(ConstantValue value, int token) {
  if (fePragmaClass < 0 || value.kind != classType(fePragmaClass)) return 0;
  if (fePragmaNameField < 0 || fePragmaOptionsField < 0)
    feAstError(token, 'core pragma requires name and options fields');
  var name = value.elements[fePragmaNameField];
  if (name.kind != tString)
    feAstError(token, 'core pragma name requires String');
  var flags = 0;
  if (name.text == 'dartc:no-gc') flags = contractNoGc;
  if (name.text == 'dartc:managed-allocate') flags = contractAllocate;
  if (name.text == 'dartc:may-gc') flags = contractMayGc;
  if (flags != 0 && value.elements[fePragmaOptionsField].kind != tNull)
    feAstError(token, 'dartc function pragmas do not accept options');
  return flags;
}

void feCheckMetadata(
  List<AstExpression> metadata,
  int owner, [
  int function = -1,
]) {
  if (metadata.isEmpty) return;
  feConstants.localTypes = feFlow.types;
  var scope = feConstants.lexicalClass;
  feConstants.lexicalClass = owner;
  var flags = 0;
  var token = -1;
  var i = 0;
  while (i < metadata.length) {
    var expression = metadata[i];
    var value = evaluateMetadataConstant(feConstants, expression);
    var annotation = fePragmaFlags(value, expression.token);
    if (annotation != 0) {
      if (function < 0)
        feAstError(
          expression.token,
          'dartc function pragma requires a function body',
        );
      flags |= annotation;
      if (token < 0) token = expression.token;
    }
    i++;
  }
  feConstants.lexicalClass = scope;
  if (flags != 0) functions[function].contract = FunctionContract(flags, token);
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
  while (i < syntax.functions.length) {
    if (syntax.functions[i].external)
      feCheckMetadata(syntax.functions[i].metadata, -1);
    i++;
  }
  i = 0;
  while (i < syntax.typedefs.length) {
    var node = syntax.typedefs[i];
    feCheckMetadata(node.metadata, -1);
    if (node.typeParameters.isNotEmpty) {
      var symbol = symbolOwnDeclaration(
        feSymbols,
        feTokens[node.token].source,
        node.name,
      );
      var alias = feSymbols.aliases[feSymbols.declarations[symbol].target];
      var scope = feConstants.typeScope;
      feConstants.typeScope = alias.parameters;
      for (var parameter in node.typeParameters) {
        feCheckMetadata(parameter.metadata, -1);
      }
      feConstants.typeScope = scope;
    }
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
    field = 0;
    while (field < node.staticFields.length) {
      feCheckMetadata(node.staticFields[field].metadata, i);
      field++;
    }
    i++;
  }
}

void feRegisterConstantConstructors() {
  var function = 1;
  while (function < feFunctionNodes.length) {
    if (feConstructors[function] == 1 && feFunctionNodes[function].constant) {
      var owner = feOwners[function];
      var fields = <int>[];
      var parameterTypes = <int>[];
      var fieldStart = feClassFieldStarts[owner];
      var field = 0;
      while (field < feClassFieldCounts[owner]) {
        fields.add(feFieldTypes[fieldStart + field]);
        field++;
      }
      var start = 1;
      var p = 0;
      while (p < feFunctionNodes[function].parameters.length) {
        parameterTypes.add(functions[function].parameterTypes[start + p]);
        p++;
      }
      while (feConstants.constructors.length <= function)
        feConstants.constructors.add(null);
      feConstants.constructors[function] = ConstantConstructorInfo(
        owner,
        feClassNodes[owner],
        feFunctionNodes[function],
        feMembers[owner],
        fields,
        parameterTypes,
        feConstructorPlans[function],
      );
    }
    function++;
  }
  checkConstantConstructors(feConstants);
}

void feResolveFunctionDefaults(int f) {
  var owner = feLexicalOwner(f);
  var scope = feConstants.lexicalClass;
  var omitted = ConstantValue(tNull, tNull, 0, '');
  feConstants.localTypes = feFlow.types;
  var syntax = feFunctionNodes[f];
  feCheckMetadata(syntax.metadata, owner, f);
  feConstants.lexicalClass = owner;
  var parameters = syntax.parameters;
  var offset = feParameterOffset(f);
  if (feParamDefaults[f].isEmpty)
    feParamDefaults[f] = List<ConstantValue>.filled(
      functions[f].parameters,
      omitted,
    );
  var p = 0;
  while (p < parameters.length) {
    var parameter = parameters[p];
    feCheckMetadata(parameter.metadata, owner);
    checkParameterName(feSources, parameters, p);
    if (parameter.kind != astRequiredPositional && !parameter.required) {
      var value = omitted;
      var type = functions[f].parameterTypes[offset + p];
      var expression = parameter.defaultValue;
      if (expression != null)
        value = evaluateConstant(feConstants, expression, type, false);
      if (!typingAssignable(value.type, type) ||
          !typeIsSubtype(constantValueType(value), type))
        feAstError(
          parameter.token,
          'default value is incompatible with parameter type',
        );
      feParamDefaults[f][offset + p] = value;
    }
    p++;
  }
  feConstants.lexicalClass = scope;
}

void feResolveDefaults(int count) {
  var f = 1;
  while (f < count) {
    feResolveFunctionDefaults(f);
    f++;
  }
}

void feCheckLegacyAccessor(int getterType, int setter, int parameter) {
  var setterType = functions[setter].parameterTypes[parameter];
  if (!typeIsSubtype(getterType, setterType))
    feAstError(
      feFunctionNodes[setter].token,
      'getter type must be a subtype of setter type before language version 3.9',
    );
}

void feCheckAccessorVersions() {
  var owner = 0;
  while (owner < feMembers.length) {
    if (!sourceVersionAtLeast(feSources, feClassSources[owner], 3, 9)) {
      var members = feMembers[owner].members;
      var i = 0;
      while (i < members.length) {
        var member = members[i];
        if (member.setter >= 0) {
          var read = -1;
          if (member.staticField >= 0)
            read = globalTypes[feClassStaticGlobals[owner][member.staticField]];
          else if (member.field >= 0)
            read = feFieldTypes[feClassFieldStarts[owner] + member.field];
          else if (member.getter >= 0)
            read = functions[feMemberFunctions[owner][member.getter]].result;
          if (read >= 0)
            feCheckLegacyAccessor(
              read,
              feMemberFunctions[owner][member.setter],
              member.isStatic ? 0 : 1,
            );
        }
        i++;
      }
    }
    owner++;
  }
  var i = 0;
  while (i < feSymbols.declarations.length) {
    var declaration = feSymbols.declarations[i];
    if (declaration.setter >= 0 &&
        !sourceVersionAtLeast(feSources, declaration.source, 3, 9)) {
      var read = -1;
      if (declaration.kind == symbolGlobal)
        read = globalTypes[declaration.target];
      else if (declaration.kind == symbolProperty && declaration.target >= 0)
        read = functions[declaration.target].result;
      if (read >= 0) feCheckLegacyAccessor(read, declaration.setter, 0);
    }
    i++;
  }
}

void feDefaultArgument(int function, int parameter, int token) {
  feConstantValue(
    feParamDefaults[function][parameter],
    functions[function].parameterTypes[parameter],
    token,
  );
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
    if (child.kind == tFunction) {
      feCallableType(child.integer, feAt);
      kind = typeKindFunction;
    }
    if (typeIsList(child.kind) || typeIsClass(child.kind)) {
      kind = typeKindList;
      if (typeIsClass(child.kind)) kind = typeKindClass;
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
  var data = constantData.length;
  constantData.add(ConstantData(value.kind, kinds, values));
  feConstantObjects.add(ConstantObject(getter, slot, state, data));
  return getter;
}

void feConstantValue(ConstantValue value, int type, int token) {
  if (value.kind == tFunction)
    feFunctionReference(value.integer, token);
  else if (value.kind == tString)
    feOperand(opString, internString(value.text));
  else if (typeIsList(value.kind) || typeIsClass(value.kind))
    feCall(feConstantGetter(value), 0);
  else
    feInteger(value.integer, value.kind);
  feConvertValue(constantValueType(value), type, token);
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
    var type = constantData[object.data].type;
    feOperand(opConstantData, object.data);
    var factory = bListFromData;
    if (typeIsClass(type)) factory = bObjectFromData;
    feBuiltinTyped(factory, 1, type);
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
  var offset = feParameterOffset(function);
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
      feLowerInContext(
        expression,
        functions[function].parameterTypes[offset + argument - start],
      );
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
    var type = functions[function].parameterTypes[offset + parameter];
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
      feDefaultArgument(function, offset + parameter, call.token);
    parameter++;
  }
  return parameters.length;
}

class FeListLiteral {
  final int context;
  final int slot;
  int inferred = -1;

  FeListLiteral(this.context, this.slot);

  void call(AstStatement body) {
    feLowerListElement(body.expressions[0], this);
  }
}

int feLowerList(AstExpression expression, int context) {
  var element = -1;
  if (expression.typeArguments.isNotEmpty)
    element = resolveType(feSymbols, expression.typeArguments[0]);
  else if (context >= 0 && typeIsList(context))
    element = typeArgument(context);
  var type = listType(element < 0 ? tDynamic : element);
  var allocation = ir.length;
  feBuiltinTyped(bListNew, 0, type);
  var literal = FeListLiteral(element, feTemp(type));
  feOperand(opStoreLocal, literal.slot);
  for (var child in expression.children) feLowerListElement(child, literal);
  if (element < 0) element = literal.inferred;
  if (element < 0) element = tDynamic;
  type = listType(element);
  // Resolve the allocation and its local before the stack IR enters SSA.
  irTypes[allocation] = type;
  feSlotTypes[literal.slot] = type;
  feOperand(opLoadLocal, literal.slot);
  return type;
}

void feAppendListElement(FeListLiteral literal, int type, int token) {
  literal.inferred = joinTypes(literal.inferred, type);
  if (literal.context >= 0) type = feConvertValue(type, literal.context, token);
  var value = feTemp(type);
  feOperand(opStoreLocal, value);
  feOperand(opLoadLocal, literal.slot);
  feOperand(opLoadLocal, value);
  feBuiltin(bListAdd, 2);
  feEmit(opPop);
}

void feLowerListElement(AstExpression expression, FeListLiteral literal) {
  if (expression.kind == astIfElement) {
    feFlow = flowSplit(feFlow);
    var otherwise = <int>[];
    var falseFlow = feConditionJumps(expression.children[0], false, otherwise);
    feLowerListElement(expression.children[1], literal);
    var trueFlow = feFlow;
    if (expression.children.length == 3) {
      var done = feJump(opJump);
      fePatchJumps(otherwise, ir.length);
      feFlow = falseFlow;
      feLowerListElement(expression.children[2], literal);
      fePatch(done, ir.length);
    } else {
      fePatchJumps(otherwise, ir.length);
      feFlow = falseFlow;
    }
    feFlow = flowUnsplit(feJoinFlow(trueFlow, feFlow));
  } else if (expression.kind == astForElement) {
    var loop = expression.loop!;
    if (loop.kind == astForInStatement)
      feLowerForIn(loop, literal);
    else
      feLowerWhileFor(loop, literal);
  } else if (expression.kind == astSpreadElement) {
    feLowerListSpread(expression, literal);
  } else if (expression.kind == astNullAwareElement) {
    if (!sourceVersionAtLeast(
      feSources,
      feTokens[expression.token].source,
      3,
      8,
    ))
      feAstError(
        expression.token,
        'null-aware elements require language version 3.8',
      );
    var context = literal.context;
    if (context >= 0 && context != tVoid) context = nullableType(context);
    var source = expression.children[0];
    var type = feLowerAssignedValue(source, context);
    var value = feTemp(type);
    feOperand(opStoreLocal, value);
    var skip = feJumpIfNull(value);
    var element = typingNonNull(type);
    feOperand(opLoadLocal, value);
    feNarrowValue(type, element);
    feAppendListElement(literal, element, source.token);
    fePatch(skip, ir.length);
  } else {
    var type = feLowerAssignedValue(expression, literal.context);
    feAppendListElement(literal, type, expression.token);
  }
}

void feLowerListSpread(AstExpression expression, FeListLiteral literal) {
  var source = expression.children[0];
  var context = literal.context < 0 ? -1 : listType(literal.context);
  var type = feLowerHint(source, context);
  var nullAware = expression.text == '...?';
  var element = typingIterableElement(type, nullAware);
  if (element < 0)
    feAstError(source.token, 'spread requires a compatible iterable');
  if (literal.context >= 0 && !typingAssignable(element, literal.context))
    feAstError(
      source.token,
      'spread element type is incompatible with the List',
    );
  literal.inferred = joinTypes(literal.inferred, element);
  var receiver = feTemp(type);
  feOperand(opStoreLocal, receiver);
  var skip = -1;
  FlowState? skipped;
  if (nullAware) {
    skipped = feNullBranch(source, type);
    skip = feJumpIfNull(receiver);
    receiver = feNonNullReceiver(receiver);
    type = feSlotTypes[receiver];
  }
  var iterableType = type;
  if (!typeIsList(iterableType)) iterableType = listType(element);
  feOperand(opLoadLocal, receiver);
  feConvertValue(type, iterableType, source.token);
  var iterable = feTemp(iterableType);
  feOperand(opStoreLocal, iterable);
  var length = feTemp(tInt);
  feOperand(opLoadLocal, iterable);
  feBuiltin(bListLength, 1);
  feOperand(opStoreLocal, length);
  var index = feTemp(tInt);
  feInteger(0, tInt);
  feOperand(opStoreLocal, index);
  var repeat = ir.length;
  feOperand(opLoadLocal, index);
  feOperand(opLoadLocal, length);
  feEmit(opLt);
  var done = feJump(opJumpFalse);
  feOperand(opLoadLocal, iterable);
  feOperand(opLoadLocal, index);
  feBuiltinTyped(bListGet, 2, element);
  feAppendListElement(literal, element, expression.token);
  feOperand(opLoadLocal, index);
  feInteger(1, tInt);
  feEmit(opAdd);
  feOperand(opStoreLocal, index);
  feOperand(opJump, repeat);
  fePatch(done, ir.length);
  if (skipped != null) {
    fePatch(skip, ir.length);
    feFlow = flowUnsplit(feJoinFlow(feFlow, skipped));
  }
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
  if (builtin == bHostRead ||
      builtin == bHostReadIfExists ||
      builtin == bHostFinish)
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
  if (builtin == bHostReadIfExists && call.children.length != 2 ||
      builtin == bHostCurrentDirectory && call.children.length != 1)
    feAstError(call.token, 'host argument count');
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
    if (call.text == astCallNew)
      feAstError(call.token, 'new cannot invoke a static method');
    return feLowerPointerBinding(call);
  }
  if (call.typeArguments.length != 0)
    feAstError(call.token, 'nongeneric call does not accept type arguments');
  if (declaration.source == sourceCore &&
      name == 'List' &&
      member == 'filled') {
    if (call.text == astCallValue)
      feAstError(call.token, 'constructor tear-off invocation is unsupported');
    var lengthArgument = -1;
    var valueArgument = -1;
    var growableArgument = -1;
    var argument = 1;
    while (argument < call.children.length) {
      var expression = call.children[argument];
      if (expression.kind == astNamedArgument) {
        if (expression.text != 'growable')
          feAstError(expression.token, 'unsupported List.filled argument');
        if (growableArgument >= 0)
          feAstError(expression.token, 'duplicate growable argument');
        growableArgument = argument;
      } else if (lengthArgument < 0) {
        lengthArgument = argument;
      } else if (valueArgument < 0) {
        valueArgument = argument;
      } else {
        feAstError(
          expression.token,
          'too many List.filled positional arguments',
        );
      }
      argument++;
    }
    if (lengthArgument < 0 || valueArgument < 0)
      feAstError(call.token, 'List.filled requires length and value');
    var element = -1;
    if (receiver.typeArguments.length != 0) {
      if (receiver.typeArguments.length != 1)
        feAstError(receiver.token, 'List requires one type argument');
      element = resolveType(feSymbols, receiver.typeArguments[0]);
    } else if (context > 0 && typeIsList(context)) {
      element = typeArgument(context);
    }
    var lengthSlot = -1;
    var valueSlot = -1;
    var growableSlot = -1;
    var valueType = -1;
    argument = 1;
    while (argument < call.children.length) {
      var expression = call.children[argument];
      if (argument == lengthArgument) {
        feLowerInContext(expression, tInt);
        lengthSlot = feTemp(tInt);
        feOperand(opStoreLocal, lengthSlot);
      } else if (argument == valueArgument) {
        if (element < 0)
          valueType = feLowerHint(expression, -1);
        else
          valueType = feLowerInContext(expression, element);
        valueSlot = feTemp(valueType);
        feOperand(opStoreLocal, valueSlot);
      } else {
        feLowerBoolean(expression.children[0]);
        growableSlot = feTemp(tBool);
        feOperand(opStoreLocal, growableSlot);
      }
      argument++;
    }
    feOperand(opLoadLocal, lengthSlot);
    feOperand(opLoadLocal, valueSlot);
    if (growableSlot >= 0)
      feOperand(opLoadLocal, growableSlot);
    else
      feInteger(0, tBool);
    if (element < 0) element = valueType;
    var type = listType(element);
    feBuiltinTyped(bListFilled, 3, type);
    return type;
  }
  if (declaration.source == sourceCore &&
      name == 'String' &&
      member == 'fromCharCodes') {
    if (call.text == astCallValue)
      feAstError(call.token, 'constructor tear-off invocation is unsupported');
    if (call.children.length != 2)
      feAstError(call.token, 'String.fromCharCodes requires one List argument');
    var count = feLowerBuiltinArguments(call, bStringFromCodes);
    feBuiltin(bStringFromCodes, count);
    return tString;
  }
  if (declaration.source == sourceCore && name == 'int' && member == 'parse') {
    if (call.text == astCallNew)
      feAstError(call.token, 'new cannot invoke a static method');
    var count = feLowerBuiltinArguments(call, bIntParse);
    feBuiltin(bIntParse, count);
    return tInt;
  }
  feAstError(call.token, 'unsupported static call ' + name + '.' + member);
}

FunctionSignature feCallSignature(AstExpression call, int type) {
  if (call.typeArguments.isNotEmpty)
    feAstError(call.token, 'nongeneric call does not accept type arguments');
  if (!typeIsFunction(type))
    feAstError(
      call.token,
      'calling a value requires a concrete non-nullable function type',
    );
  var signature = functionSignature(type);
  if (signature.required != signature.parameters.length)
    feAstError(
      call.token,
      'function-value calls with optional parameters are not supported',
    );
  if (call.children.length - 1 != signature.parameters.length)
    feAstError(call.token, 'function-value argument count');
  var i = 1;
  while (i < call.children.length) {
    if (call.children[i].kind == astNamedArgument)
      feAstError(
        call.children[i].token,
        'function-value arguments must be positional',
      );
    i++;
  }
  return signature;
}

void feCallableBox(int type, int token) {
  if (type == tVoid)
    feBuiltinTyped(bBoxRef, 1, tDynamic);
  else
    feConvertValue(type, tDynamic, token);
}

void fePrepareFunctionCall(int type) {
  var value = feTemp(type);
  feOperand(opStoreLocal, value);
  feOperand(opLoadLocal, value);
  feBuiltin(bFunctionEntry, 1);
  feOperand(opLoadLocal, value);
}

int feInvokeFunction(AstExpression call, FunctionSignature signature) {
  feBuiltin(bFunctionInvoke, signature.parameters.length + 2);
  return feConvertValue(tDynamic, signature.result, call.token);
}

int feLowerValueCall(AstExpression call, int type) {
  if (feClassType(type)) {
    var method = feMethod(typeArgument(type), 'call', false);
    if (method >= 0) {
      var count = feLowerArguments(call, 1, method);
      feCall(method, count + 1);
      return functions[method].result;
    }
  }
  var signature = feCallSignature(call, type);
  fePrepareFunctionCall(type);
  var i = 0;
  while (i < signature.parameters.length) {
    var expression = call.children[i + 1];
    var argument = feLowerInContext(expression, signature.parameters[i]);
    feCallableBox(argument, expression.token);
    i++;
  }
  return feInvokeFunction(call, signature);
}

int feLowerMemberValueCall(AstExpression call, int type, String member) {
  var receiver = feTemp(type);
  feOperand(opStoreLocal, receiver);
  var owner = typeArgument(type);
  var binding =
      feMembers[owner].members[lookupMember(feMembers[owner], member)];
  var value = -1;
  if (binding.getter >= 0)
    value = functions[feMemberFunctions[owner][binding.getter]].result;
  else if (binding.field >= 0)
    value = feFieldTypes[feClassFieldStarts[owner] + binding.field];
  else
    feAstError(call.token, 'member has no getter: ' + member);
  if (value == tNever) {
    feLowerNeverArguments(call);
    feOperand(opLoadLocal, receiver);
    return feReadBoundMember(owner, binding, call.token);
  }
  if (feClassType(value)) {
    var method = feMethod(typeArgument(value), 'call', false);
    if (method >= 0) {
      var count = feLowerArguments(call, 1, method);
      var arguments = List<int>.filled(count, -1);
      var i = count - 1;
      while (i >= 0) {
        arguments[i] = feTemp(functions[method].parameterTypes[i + 1]);
        feOperand(opStoreLocal, arguments[i]);
        i--;
      }
      feOperand(opLoadLocal, receiver);
      feReadBoundMember(owner, binding, call.token);
      for (var argument in arguments) feOperand(opLoadLocal, argument);
      feCall(method, count + 1);
      return functions[method].result;
    }
  }
  var signature = feCallSignature(call, value);
  var arguments = <int>[];
  var i = 0;
  while (i < signature.parameters.length) {
    var expression = call.children[i + 1];
    var argument = feLowerInContext(expression, signature.parameters[i]);
    feCallableBox(argument, expression.token);
    var slot = feTemp(tDynamic);
    feOperand(opStoreLocal, slot);
    arguments.add(slot);
    i++;
  }
  feOperand(opLoadLocal, receiver);
  feReadBoundMember(owner, binding, call.token);
  fePrepareFunctionCall(value);
  i = 0;
  while (i < arguments.length) {
    feOperand(opLoadLocal, arguments[i]);
    i++;
  }
  return feInvokeFunction(call, signature);
}

int feLowerStaticMemberCall(
  AstExpression call,
  int owner,
  MemberBinding member,
) {
  if (call.text == astCallNew)
    feAstError(call.token, 'new requires a constructor');
  if (member.method >= 0) {
    var function = feMemberFunctions[owner][member.method];
    var count = feLowerArguments(call, 1, function);
    feCall(function, count);
    return functions[function].result;
  }
  var type = feReadStaticMember(owner, member, call.token);
  if (type == tNever) return feLowerNeverArguments(call);
  return feLowerValueCall(call, type);
}

int feLowerMemberCall(AstExpression call, AstExpression callee) {
  var receiver = callee.children[0];
  var member = callee.text;
  if (receiver.kind == astFunctionExpression && member == 'call')
    return feLowerImmediateCall(call, receiver);
  var type = feLowerExpression(receiver);
  if (type == tNever) return feLowerNeverArguments(call);
  if (typeIsFunction(type) && member == 'call')
    return feLowerValueCall(call, type);
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
      if (call.text != astCallValue) {
        var index = lookupMember(feMembers[owner], member);
        if (index < 0) feAstError(call.token, 'unknown member ' + member);
        var binding = feMembers[owner].members[index];
        if (binding.isStatic)
          feAstError(
            call.token,
            'static member cannot be accessed through an instance',
          );
        return feLowerMemberValueCall(call, type, member);
      }
      var value = feReadMember(type, member, call.token);
      if (value == tNever) return feLowerNeverArguments(call);
      return feLowerValueCall(call, value);
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
    if (member == 'insert') {
      if (call.children.length != 3)
        feAstError(call.token, 'argument count for List.insert');
      feLowerInContext(call.children[1], tInt);
      feLowerInContext(call.children[2], typeArgument(type));
      feBuiltin(bListInsert, 3);
      return tVoid;
    }
    if (member == 'removeAt') {
      if (call.children.length != 2)
        feAstError(call.token, 'argument count for List.removeAt');
      feLowerInContext(call.children[1], tInt);
      var element = typeArgument(type);
      feBuiltinTyped(bListRemoveAt, 2, element);
      return element;
    }
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

int feLowerImmediateCall(AstExpression call, AstExpression expression) {
  var function = fePrepareFunctionExpression(expression, -1);
  var context = functions[function].closureLayout != null;
  if (context) feCreateClosure(function, expression.token);
  var count = feLowerArguments(call, 1, function);
  feCall(function, count + (context ? 1 : 0));
  return functions[function].result;
}

void feLowerConstructor(int function) {
  var syntax = feFunctionNodes[function];
  var plan = feConstructorPlans[function];
  if (plan.redirectTarget >= 0) {
    var call = syntax.initializers[0].expression;
    checkArgumentOrder(feSources, call);
    var bodyBindings = feBindings;
    feBindings = bodyBindings.withReceiver(-1);
    feOperand(opLoadLocal, 0);
    var count = feLowerArguments(call, 1, plan.redirectTarget);
    feCall(plan.redirectTarget, count + 1);
    feBindings = bodyBindings;
    feEmit(opReturn);
    return;
  }
  var bodyBindings = feBindings;
  var owner = feOwners[function];
  var steps = plan.steps;
  var stepIndex = 0;
  while (stepIndex < steps.length) {
    var step = steps[stepIndex];
    var field = feClassFieldStarts[owner] + step.field;
    var fieldType = feFieldTypes[field];
    feOperand(opLoadLocal, 0);
    feOperand(opInt, feFieldIndices[field]);
    if (step.kind == constructorDeclaration) {
      feLowerInitializer(
        feFieldNodes[field],
        feFieldBindings[field],
        fieldType,
      );
    } else if (step.kind == constructorFormal) {
      var parameter = 1 + step.index;
      feOperand(opLoadLocal, step.index + 1);
      feConvertValue(
        functions[function].parameterTypes[parameter],
        fieldType,
        syntax.parameters[step.index].token,
      );
    } else {
      feBindings = bodyBindings.withReceiver(-1);
      feLowerInContext(syntax.initializers[step.index].expression, fieldType);
    }
    feBuiltinTyped(bObjectSet, 3, fieldType);
    feEmit(opPop);
    stepIndex++;
  }
  feBindings = bodyBindings;
  var body = syntax.body;
  if (body != null) feLowerStatement(body);
  feOperand(opLoadLocal, 0);
  feEmit(opReturn);
}

int feLowerConstructorCall(
  AstExpression call,
  int owner,
  String rawName,
  int token,
) {
  if (call.text == astCallValue)
    feAstError(call.token, 'constructor tear-off invocation is unsupported');
  var name = constructorSelector(feSources, rawName, token);
  feCheckPrivate(owner, name, token);
  var ordinal = lookupConstructor(feMembers[owner], name);
  if (ordinal < 0) feAstError(token, 'unknown constructor');
  var constructor = feClassConstructors[owner][ordinal];
  var count = feLowerArguments(call, 1, constructor);
  var values = List<int>.filled(count, -1);
  var parameter = count - 1;
  while (parameter >= 0) {
    var type = functions[constructor].parameterTypes[1 + parameter];
    values[parameter] = feTemp(type);
    feOperand(opStoreLocal, values[parameter]);
    parameter--;
  }
  feOperand(opDescriptor, owner);
  feBuiltinTyped(bObjectNew, 1, classType(owner));
  parameter = 0;
  while (parameter < count) {
    feOperand(opLoadLocal, values[parameter]);
    parameter++;
  }
  feCall(constructor, count + 1);
  return classType(owner);
}

int feLowerCall(AstExpression call, int context) {
  checkArgumentOrder(feSources, call);
  var callee = feWithReceiver(call.children[0]);
  var symbol = feExpressionSymbol(callee, false);
  var classArguments = call.typeArguments;
  if ((callee.kind == astName || callee.kind == astMember) &&
      callee.typeArguments.isNotEmpty) {
    if (classArguments.isNotEmpty)
      feAstError(callee.token, 'duplicate constructor type arguments');
    classArguments = callee.typeArguments;
  }
  var classType = feConstructorType(symbol, classArguments, callee.token);
  var classOwner = classType < 0 ? -1 : resolvedTypeClassOwner(classType);
  if (classOwner >= 0) {
    var physicalCall = call;
    if (call.typeArguments.isNotEmpty)
      physicalCall = AstExpression(
        call.kind,
        call.text,
        call.children,
        const <AstType>[],
        call.token,
      );
    return feLowerConstructorCall(physicalCall, classOwner, '', callee.token);
  }
  var staticOwner = feStaticOwner(callee);
  if (staticOwner >= 0) {
    var index = lookupMember(feMembers[staticOwner], callee.text);
    if (index >= 0 && feMembers[staticOwner].members[index].isStatic) {
      var member = feStaticBinding(staticOwner, callee.text, callee.token);
      return feLowerStaticMemberCall(call, staticOwner, member);
    }
  }
  if (symbol < 0 && callee.kind == astMember) {
    var receiver = callee.children[0];
    var owner = feExpressionSymbol(receiver, false);
    var classType = feConstructorType(
      owner,
      receiver.typeArguments,
      receiver.token,
    );
    var classOwner = classType < 0 ? -1 : resolvedTypeClassOwner(classType);
    if (classOwner >= 0) {
      var type = feLowerConstructorCall(
        call,
        classOwner,
        callee.text,
        callee.token,
      );
      var declaration = feSymbols.declarations[owner];
      if (call.text != astCallNew && declaration.kind == symbolAlias)
        return feConvertValue(type, classType, call.token);
      return type;
    }
    if (owner >= 0 && feSymbols.declarations[owner].kind == symbolType)
      return feLowerStaticCall(call, owner, context);
  }
  if (call.text == astCallNew)
    feAstError(call.token, 'new requires a constructor');
  if (callee.kind == astFunctionExpression)
    return feLowerImmediateCall(call, callee);
  if (callee.kind == astName && callee.binding >= 0) {
    var local = feBindings.variables[callee.binding].function;
    if (local >= 0) {
      var function = feLocalStart + local;
      var context = functions[function].closureLayout != null;
      if (context) feReadLocal(callee.binding, callee.token);
      var count = feLowerArguments(call, 1, function);
      feCall(function, count + (context ? 1 : 0));
      return functions[function].result;
    }
  }
  if (symbol >= 0) {
    var declaration = feSymbols.declarations[symbol];
    if (declaration.kind == symbolFunction) {
      var function = declaration.target;
      var count = feLowerArguments(call, 1, function);
      feCall(function, count);
      return functions[function].result;
    }
    if (declaration.kind == symbolBuiltin)
      return feLowerBuiltinCall(call, declaration.target);
    var value = feLoadDeclaration(symbol, callee.token);
    if (value == tNever) return feLowerNeverArguments(call);
    return feLowerValueCall(call, value);
  }
  if (callee.kind == astMember) return feLowerMemberCall(call, callee);
  var value = feLowerExpression(callee);
  if (value == tNever) return feLowerNeverArguments(call);
  return feLowerValueCall(call, value);
}

int feLowerMember(AstExpression expression) {
  var owner = feStaticOwner(expression);
  if (owner >= 0)
    return feReadStaticMember(
      owner,
      feStaticBinding(owner, expression.text, expression.token),
      expression.token,
    );
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
  if ((typeIsFunction(type) || type == tFunction) && member == 'call')
    return type;
  if (feClassType(type)) {
    var owner = typeArgument(type);
    feCheckPrivate(owner, member, token);
    var index = lookupMember(feMembers[owner], member);
    if (index < 0) feAstError(token, 'unknown member ' + member);
    var binding = feMembers[owner].members[index];
    if (binding.isStatic)
      feAstError(token, 'static member cannot be accessed through an instance');
    return feReadBoundMember(owner, binding, token);
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
  if (member.isStatic) return feReadStaticMember(owner, member, token);
  if (member.method >= 0)
    return feCreateBoundMethod(feMemberFunctions[owner][member.method], token);
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
      if (feBindings.variables[binding].function >= 0)
        feAstError(expression.token, 'cannot assign a local function');
      if (feBindings.variables[binding].constant)
        feAstError(expression.token, 'cannot assign a constant');
      feLocalSlot(binding, expression.token);
      return FeLvalue(feBindingTypes[binding], 0, -1, -1, binding, -1);
    }
  }
  var staticOwner = feStaticOwner(expression);
  if (staticOwner >= 0) {
    var member = feStaticBinding(
      staticOwner,
      expression.text,
      expression.token,
    );
    var global = -1;
    var type = -1;
    var setter = -1;
    if (member.setter >= 0) {
      setter = feMemberFunctions[staticOwner][member.setter];
      type = functions[setter].parameterTypes[0];
    } else if (member.staticField >= 0) {
      global = feClassStaticGlobals[staticOwner][member.staticField];
      var modifier = feGlobalNodes[global].modifier;
      if (modifier == 'final' || modifier == 'const')
        feAstError(expression.token, 'cannot assign a final field');
      type = feGlobalType(global);
    } else {
      feAstError(expression.token, 'member has no setter: ' + member.name);
    }
    if (reading) feStaticReadType(staticOwner, member, expression.token);
    var target = FeLvalue(type, setter >= 0 ? 5 : 0, -1, -1, -1, global);
    target.owner = staticOwner;
    target.member = lookupMember(feMembers[staticOwner], member.name);
    target.setter = setter;
    return target;
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
        functions[setter].parameterTypes[0],
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
    if (member.isStatic)
      feAstError(
        expression.token,
        'static member cannot be accessed through an instance',
      );
    if (member.setter >= 0) {
      var setter = feMemberFunctions[owner][member.setter];
      var receiver = feTemp(receiverType);
      feOperand(opStoreLocal, receiver);
      var target = FeLvalue(
        functions[setter].parameterTypes[1],
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
  if ((target.container == 0 || target.container == 5) && target.owner >= 0)
    return feReadStaticMember(
      target.owner,
      feMembers[target.owner].members[target.member],
      token,
    );
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
    if (!fePromotable(target.binding))
      feFlow.types[target.binding] = target.type;
  }
}

void feWriteLvalue(FeLvalue target, int token) {
  if (target.binding >= 0 &&
      feBindings.variables[target.binding].finalVariable &&
      (feBindings.variables[target.binding].outer >= 0 ||
          feFlow.assignments[target.binding] != flowUnassigned)) {
    feAstError(token, 'final variable might already be assigned');
  }
  if (target.container == 3) return;
  if (target.container == 0) {
    if (target.binding >= 0 && feCellBinding(target.binding)) {
      var value = feTemp(target.type);
      feOperand(opStoreLocal, value);
      feOperand(opLoadLocal, feBindingSlots[target.binding]);
      feOperand(opInt, 0);
      feOperand(opLoadLocal, value);
      feBuiltinTyped(bObjectSet, 3, target.type);
      return;
    }
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
    var type = feLowerAssignedValue(source, target.type);
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
  if (feFlow.soundFlow && !typeCanBeNull(left)) flowUnreachable(feFlow);
  var source = expression.children[1];
  var context = target.type;
  if (target.binding >= 0) context = left;
  var right = feLowerAssignedValue(source, context);
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
  if (target.binding >= 0 && fePromotable(target.binding))
    flowNull(feFlow, target.binding, false);
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
  if (source.kind == astName &&
      source.binding >= 0 &&
      fePromotable(source.binding))
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
  if (expression.kind == astSwitchExpression)
    return feLowerSwitchExpression(expression, -1);
  expression = feWithReceiver(expression);
  var kind = expression.kind;
  if (kind == astNullAware) return feLowerNullAware(expression, -1);
  if (kind == astCascade) return feLowerCascade(expression, -1);
  if (kind == astImplicitReceiver) {
    feOperand(opLoadLocal, feImplicitReceiverSlot);
    return feSlotTypes[feImplicitReceiverSlot];
  }
  if (kind == astFunctionExpression)
    return feLowerFunctionExpression(expression, -1);
  if ((kind == astName || kind == astMember) &&
      expression.typeArguments.length != 0)
    feAstError(expression.token, 'type application values are unsupported');
  if (kind == astInteger) {
    feOperand(opInt, decodeIntegerLiteral(feSources, expression));
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
    var owner = feStaticOwner(expression);
    if (owner >= 0)
      return feReadStaticMember(
        owner,
        feStaticBinding(owner, expression.text, expression.token),
        expression.token,
      );
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
  if (kind == astCall) {
    if (expression.constant) return feLowerHint(expression, -1);
    return feLowerCall(expression, -1);
  }
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
      if (binding >= 0 && fePromotable(binding)) {
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
    if (isNegatedIntegerLiteral(expression)) {
      feOperand(opInt, decodeIntegerLiteral(feSources, expression));
      return tInt;
    }
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

FlowState feNullBranch(AstExpression source, int type) {
  feFlow = flowSplit(feFlow);
  var skipped = flowCopy(feFlow);
  if (source.kind == astName &&
      source.binding >= 0 &&
      fePromotable(source.binding)) {
    flowNull(skipped, source.binding, true);
    flowNull(feFlow, source.binding, false);
    if (type == tNull) feFlow.types[source.binding] = tNever;
  } else {
    if (feFlow.soundFlow && !typeCanBeNull(type)) flowUnreachable(skipped);
    if (type == tNull) flowUnreachable(feFlow);
  }
  return skipped;
}

int feJumpIfNull(int receiver) {
  if (typeCanBeNull(feSlotTypes[receiver])) {
    feOperand(opLoadLocal, receiver);
    feInteger(0, tNull);
    feEmit(opEq);
  } else {
    feInteger(0, tBool);
  }
  return feJump(opJumpTrue);
}

int feNonNullReceiver(int receiver) {
  var type = feSlotTypes[receiver];
  var promoted = typingNullAssertion(type);
  feOperand(opLoadLocal, receiver);
  feNarrowValue(type, promoted);
  var slot = feTemp(promoted);
  feOperand(opStoreLocal, slot);
  return slot;
}

int feLowerNullAware(AstExpression expression, int context) {
  var source = expression.children[0];
  var body = expression.children[1];
  var symbol = feExpressionSymbol(source, false);
  if (symbol >= 0 &&
      (declarationClassOwner(feSymbols, symbol) >= 0 ||
          feSymbols.declarations[symbol].kind == symbolType)) {
    // A type qualifier is not a nullable value; retain normal static lookup.
    var access = astImplicitReceiverAccess(body);
    var receiver = access.children[0];
    access.children[0] = source;
    var type = feLowerHint(body, context);
    access.children[0] = receiver;
    return type;
  }
  var type = feLowerExpression(source);
  if (type == tVoid)
    feAstError(source.token, 'void expression cannot be used as a value');
  var receiver = feTemp(type);
  feOperand(opStoreLocal, receiver);
  var skipped = feNullBranch(source, type);
  var skip = feJumpIfNull(receiver);
  var previous = feImplicitReceiverSlot;
  feImplicitReceiverSlot = feNonNullReceiver(receiver);
  var value = feLowerHint(body, context);
  var result = value == tVoid ? tVoid : nullableType(value);
  feConvertValue(value, result, body.token);
  var done = feJump(opJump);
  fePatch(skip, ir.length);
  feInteger(0, result);
  fePatch(done, ir.length);
  feFlow = flowUnsplit(feJoinFlow(feFlow, skipped));
  feImplicitReceiverSlot = previous;
  return result;
}

int feLowerCascade(AstExpression expression, int context) {
  var source = expression.children[0];
  var type = feLowerHint(source, context);
  if (type == tVoid)
    feAstError(source.token, 'void expression cannot be used as a value');
  var receiver = feTemp(type);
  feOperand(opStoreLocal, receiver);
  var previous = feImplicitReceiverSlot;
  feImplicitReceiverSlot = receiver;
  var skip = -1;
  FlowState? nullFlow;
  if (expression.text == '?..') {
    nullFlow = feNullBranch(source, type);
    skip = feJumpIfNull(receiver);
    feImplicitReceiverSlot = feNonNullReceiver(receiver);
  }
  var section = 1;
  while (section < expression.children.length) {
    feLowerExpression(expression.children[section]);
    feEmit(opPop);
    section++;
  }
  if (nullFlow != null) {
    fePatch(skip, ir.length);
    feFlow = flowUnsplit(feJoinFlow(feFlow, nullFlow));
  }
  feImplicitReceiverSlot = previous;
  feOperand(opLoadLocal, receiver);
  return type;
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
  if (source.kind == astName &&
      source.binding >= 0 &&
      fePromotable(source.binding))
    flowNull(feFlow, source.binding, true);
  else if (feFlow.soundFlow && !typeCanBeNull(left))
    flowUnreachable(feFlow);
  var right = feLowerHint(expression.children[1], context);
  var result = typingCoalescing(left, right);
  feConvertValue(right, result, expression.children[1].token);
  var rightFlow = feFlow;
  var done = feJump(opJump);
  fePatch(present, ir.length);
  feFlow = afterLeft;
  if (source.kind == astName &&
      source.binding >= 0 &&
      fePromotable(source.binding))
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
  feCheckMetadata(variable.metadata, feLexicalOwner(feFunction));
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
    value = feLowerAssignedValue(variable.initializer[0], type);
  else
    feInteger(0, type);
  if (type < 0) {
    if (value == tNull) value = feConvertValue(value, tDynamic, variable.token);
    type = value;
  }
  feConvertValue(value, type, variable.token);
  var cell = feCellBinding(variable.binding);
  if (cell) feAllocateCell(type);
  var slot = feTemp(cell ? tObject : type);
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
  if (!fePromotable(variable.binding)) feFlow.types[variable.binding] = type;
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
  if (statement.kind == astForInStatement && statement.variables.isEmpty)
    collectWrittenBinding(statement.expressions[1].binding, seen, written);
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

void feInferLocalResult(int local) {
  if (feLocalInferred[local]) return;
  var declaration = feLocalFunctions[local];
  var function = feLocalStart + local;
  var previous = FeFunctionState();
  ir = <int>[];
  irTypes = <int>[];
  feConstants.locals = <ConstantValue>[];
  feBreaks = <int>[];
  feContinues = <int>[];
  feBreakFlows = <FlowState>[];
  feContinueFlows = <FlowState>[];
  feLoopBreaks = <int>[];
  feLoopContinues = <int>[];
  feLabels = <ControlLabel>[];
  feReturnTypes = <int>[];
  feInitializingGlobal = -1;
  feBeginFunction(function, declaration.body!);
  var result = tNever;
  var context = feLocalContexts[local];
  var arrow = declaration.syntax.arrow;
  if (arrow != null) {
    result = feLowerAssignedValue(arrow, context);
  } else {
    var body = declaration.syntax.body;
    if (body != null) feLowerStatement(body);
    if (feFlow.reachable) result = tNull;
    var returned = feReturnTypes!;
    var i = 0;
    while (i < returned.length) {
      result = joinTypes(result, returned[i]);
      i++;
    }
  }
  previous.restore();
  if (context >= 0 && (context == tVoid || !typeIsSubtype(result, context)))
    result = context;
  functions[function].result = result;
  functions[function].callableType = -1;
  feLocalInferred[local] = true;
}

void fePrepareLocalFunction(AstFunction syntax) {
  var function = feLocalStart + syntax.local;
  feResolveFunctionDefaults(function);
  var bindings = feLocalFunctions[syntax.local].body!;
  var closure = feLocalClosures[syntax.local];
  var layout = functions[function].closureLayout;
  if (!closure.prepared) {
    closure.prepared = true;
    if (layout != null) {
      for (var binding in bindings.captures) {
        var variable = bindings.variables[binding];
        if (variable.function == syntax.local) continue;
        var original = variable.outer;
        var type = feBindingTypes[original];
        if (type < 0)
          feAstError(syntax.token, 'captured variable has no declared type');
        var declaration = bindingDeclaration(feBindings, original);
        var promoted = declaration.written ? type : feFlow.types[original];
        closure.captures.add(
          FeCapture(binding, type, promoted, feFlow.assignments[original]),
        );
        layout.fieldTypes.add(feCellBinding(original) ? tObject : type);
      }
    }
  }
  List<ConstantValue>? values;
  var i = 0;
  while (i < bindings.variables.length) {
    var variable = bindings.variables[i];
    if (variable.outer >= 0 && variable.constant) {
      var original = variable.outer;
      if (original >= feConstants.locals.length ||
          feConstants.locals[original].type < 0)
        feAstError(syntax.token, 'constant referenced before declaration');
      values ??= List<ConstantValue>.filled(
        bindings.variables.length,
        ConstantValue(-1, tNull, 0, ''),
      );
      values[i] = constantWithType(
        feConstants.locals[original],
        feFlow.types[original],
      );
    }
    i++;
  }
  feLocalConstants[syntax.local] = values;
  feInferLocalResult(syntax.local);
}

void feLowerLocalFunction(AstFunction syntax) {
  fePrepareLocalFunction(syntax);
  var function = feLocalStart + syntax.local;
  var type = functionValueType(function);
  var slot = -1;
  if (functions[function].closureLayout != null) {
    feCreateClosure(function, syntax.token);
    slot = feTemp(type);
    feOperand(opStoreLocal, slot);
  }
  if (type >= 0) {
    var binding = 0;
    while (binding < feBindings.variables.length) {
      if (feBindings.variables[binding].function == syntax.local) {
        feBindingTypes[binding] = type;
        feBindingSlots[binding] = slot;
        flowDeclare(feFlow, binding, type, true);
      }
      binding++;
    }
  }
}

int fePrepareFunctionExpression(AstExpression expression, int context) {
  var syntax = expression.function!;
  var function = feLocalStart + syntax.local;
  if (feLocalInferred[syntax.local]) return function;
  if (context >= 0) context = typeNonNullable(context);
  if (context >= 0 && typeIsFunction(context)) {
    var signature = functionSignature(context);
    var p = 0;
    while (p < syntax.parameters.length && p < signature.parameters.length) {
      if (syntax.parameters[p].type.name == '') {
        var type = signature.parameters[p];
        if (typeIsSubtype(type, tNull)) type = nullableType(tObject);
        functions[function].parameterTypes[p + feParameterOffset(function)] =
            type;
      }
      p++;
    }
    feLocalContexts[syntax.local] = signature.result;
  }
  fePrepareLocalFunction(syntax);
  return function;
}

int feAllocateClosure(int function, int token) {
  var type = feCallableType(function, token);
  feOperand(opClosureDescriptor, function);
  feBuiltinTyped(bObjectNew, 1, type);
  var closure = feTemp(type);
  feOperand(opStoreLocal, closure);
  var field = 0;
  while (field < 2) {
    feOperand(opLoadLocal, closure);
    feOperand(opInt, field);
    feFunctionReference(function, token);
    feBuiltin(field == 0 ? bFunctionType : bFunctionEntry, 1);
    feBuiltinTyped(bObjectSet, 3, tPointer);
    feEmit(opPop);
    field++;
  }
  return closure;
}

int feCreateBoundMethod(int function, int token) {
  var receiverType = functions[function].parameterTypes[0];
  var receiver = feTemp(receiverType);
  feOperand(opStoreLocal, receiver);
  var closure = feAllocateClosure(function, token);
  feOperand(opLoadLocal, closure);
  feOperand(opInt, 2);
  feOperand(opLoadLocal, receiver);
  feBuiltinTyped(bObjectSet, 3, receiverType);
  feEmit(opPop);
  feOperand(opLoadLocal, closure);
  return feSlotTypes[closure];
}

int feCreateClosure(int function, int token) {
  var layout = functions[function].closureLayout;
  if (layout == null) return feFunctionReference(function, token);
  var closure = feAllocateClosure(function, token);
  var local = function - feLocalStart;
  var bindings = feLocalFunctions[local].body!;
  var captureIndex = 0;
  for (var capture in feLocalClosures[local].captures) {
    var original = bindings.variables[capture.binding].outer;
    feOperand(opLoadLocal, closure);
    feOperand(opInt, 2 + captureIndex);
    if (feCellBinding(original))
      feOperand(opLoadLocal, feLocalSlot(original, token));
    else {
      var value = feReadLocal(original, token);
      feConvertValue(value, capture.type, token);
    }
    feBuiltinTyped(bObjectSet, 3, layout.fieldTypes[captureIndex]);
    feEmit(opPop);
    captureIndex++;
  }
  feOperand(opLoadLocal, closure);
  return feSlotTypes[closure];
}

int feLowerFunctionExpression(AstExpression expression, int context) {
  return feCreateClosure(
    fePrepareFunctionExpression(expression, context),
    expression.token,
  );
}

int feLocalResultContext(int function) {
  if (function >= feLocalStart &&
      function < feLocalStart + feLocalFunctions.length)
    return feLocalContexts[function - feLocalStart];
  return -1;
}

bool feInfersLocalResult(int function) {
  return function >= feLocalStart &&
      function < feLocalStart + feLocalFunctions.length &&
      feFunctionNodes[function].result.name == '';
}

void feLowerStatement(AstStatement statement) {
  feAt = statement.token;
  var kind = statement.kind;
  if (kind == astEmptyStatement) return;
  if (kind == astLocalFunctionStatement) {
    feLowerLocalFunction(statement.function!);
    return;
  }
  if (kind == astForInStatement) {
    feLowerForIn(statement, feLowerStatement);
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
    var returned = feReturnTypes;
    if (returned != null) {
      var type = tNull;
      if (statement.expressions.isEmpty)
        feInteger(0, tNull);
      else
        type = feLowerAssignedValue(
          statement.expressions[0],
          feLocalResultContext(feFunction),
        );
      returned.add(type);
      feEmit(opReturn);
      flowUnreachable(feFlow);
      return;
    }
    if (statement.expressions.length != 0) {
      var value = statement.expressions[0];
      var result = functions[feFunction].result;
      if (result == tVoid) {
        var context = tVoid;
        if (feInfersLocalResult(feFunction))
          context = feLocalResultContext(feFunction);
        var type = feLowerAssignedValue(value, context);
        if (type != tVoid && type != tNull)
          feAstError(value.token, 'void function cannot return a value');
        feConvertValue(type, tVoid, value.token);
      } else if (feInfersLocalResult(feFunction)) {
        var type = feLowerAssignedValue(
          value,
          feLocalResultContext(feFunction),
        );
        feConvertValue(type, result, value.token);
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
    feLowerWhileFor(statement, feLowerStatement);
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

void fePrepareGlobals(int count, List<FunctionBindings> bindings) {
  var i = 0;
  while (i < count) {
    var initializer = GlobalInitializer(
      bindings[i],
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

int feLowerInitializer(
  AstVariable syntax,
  FunctionBindings bindings,
  int context,
) {
  var previousBindings = feBindings;
  var previousTypes = feBindingTypes;
  var previousSlots = feBindingSlots;
  var previousFlow = feFlow;
  var previousConstants = feConstants.locals;
  var previousConstantTypes = feConstants.localTypes;
  feBindings = bindings;
  feBindingTypes = List<int>.filled(bindings.variables.length, -1);
  feBindingSlots = List<int>.filled(bindings.variables.length, -1);
  feConstants.locals = <ConstantValue>[];
  feConstants.localTypes = <int>[];
  feFlow = flowCreate(
    bindings.variables.length,
    sourceVersionAtLeast(feSources, feTokens[syntax.token].source, 3, 9),
  );
  var type = context;
  if (syntax.initializer.isEmpty) {
    if (type < 0) type = tDynamic;
    feInteger(0, type);
  } else {
    feAt = syntax.initializer[0].token;
    type = feLowerInContext(syntax.initializer[0], context);
  }
  feBindings = previousBindings;
  feBindingTypes = previousTypes;
  feBindingSlots = previousSlots;
  feFlow = previousFlow;
  feConstants.locals = previousConstants;
  feConstants.localTypes = previousConstantTypes;
  return type;
}

void feInferGlobal(int global) {
  var initializer = feGlobalInitializers[global];
  if (initializer.code.isNotEmpty) return;
  if (initializer.result == -1)
    feError('cannot infer global type ' + globalNames[global]);
  initializer.result = -1;
  var previous = FeFunctionState();
  feConstants.lexicalClass = feGlobalOwners[global];
  ir = <int>[];
  irTypes = <int>[];
  feSlotTypes = <int>[];
  feNextLocal = 0;
  feInitializingGlobal = global;
  var type = globalTypes[global];
  var syntax = feGlobalNodes[global];
  type = feLowerInitializer(syntax, initializer.bindings, type);
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
  previous.restore();
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

void feBeginFunction(int f, FunctionBindings bindings) {
  feFunction = f;
  feImplicitReceiverSlot = -1;
  feConstants.lexicalClass = -1;
  var owner = feLexicalOwner(f);
  feConstants.lexicalClass = owner;
  var functionSyntax = feFunctionNodes[f];
  feAt = functionSyntax.token;
  feBindings = bindings;
  feConstants.locals.clear();
  if (f >= feLocalStart) {
    var values = feLocalConstants[f - feLocalStart];
    if (values != null) {
      var i = 0;
      while (i < values.length) {
        feConstants.locals.add(values[i]);
        i++;
      }
    }
  }
  feFlow = flowCreate(
    feBindings.variables.length,
    sourceVersionAtLeast(
      feSources,
      feTokens[functionSyntax.token].source,
      3,
      9,
    ),
  );
  feBindingTypes = <int>[];
  feBindingSlots = <int>[];
  var binding = 0;
  while (binding < feBindings.variables.length) {
    feBindingTypes.add(-1);
    feBindingSlots.add(-1);
    binding++;
  }
  binding = 0;
  while (binding < feBindings.variables.length) {
    var variable = feBindings.variables[binding];
    var type = -1;
    if (variable.function >= 0)
      type = functionValueType(feLocalStart + variable.function);
    else if (variable.outer >= 0 && variable.constant)
      type = feConstants.locals[binding].type;
    if (type >= 0) {
      feBindingTypes[binding] = type;
      flowDeclare(feFlow, binding, type, true);
    }
    binding++;
  }
  feSlotTypes = <int>[];
  feNextLocal = 0;
  var context = functions[f].closureLayout;
  if (context != null && context.boundReceiver) context = null;
  var p = 0;
  while (p < functions[f].parameters) {
    feTemp(functions[f].parameterTypes[p]);
    p++;
  }
  p = context == null ? 0 : 1;
  while (p < functions[f].parameters) {
    var type = functions[f].parameterTypes[p];
    var slot = p;
    var binding = feBindings.receiver;
    var parameter = p - feParameterOffset(f);
    if (parameter >= 0) binding = functionSyntax.parameters[parameter].binding;
    if (binding >= 0) {
      if (feCellBinding(binding)) {
        feOperand(opLoadLocal, slot);
        feAllocateCell(type);
        slot = feTemp(tObject);
        feOperand(opStoreLocal, slot);
      }
      feBindLocal(binding, type, slot);
    }
    p++;
  }
  if (context != null) {
    var local = f - feLocalStart;
    var captureIndex = 0;
    for (var capture in feLocalClosures[local].captures) {
      var storageType = context.fieldTypes[captureIndex];
      feOperand(opLoadLocal, 0);
      feOperand(opInt, 2 + captureIndex);
      feBuiltinTyped(bObjectGet, 2, storageType);
      var slot = feTemp(storageType);
      feOperand(opStoreLocal, slot);
      feBindLocal(capture.binding, capture.type, slot);
      feFlow.types[capture.binding] = capture.promoted;
      feFlow.assignments[capture.binding] = capture.assignment;
      captureIndex++;
    }
    var binding = 0;
    while (binding < feBindings.variables.length) {
      if (feBindings.variables[binding].function == local) {
        feBindLocal(binding, functionValueType(f), 0);
      }
      binding++;
    }
  }
}

FunctionBindings feBindInitializer(AstVariable syntax, int owner) {
  var bindings = FunctionBindings(<LocalVariable>[], -1);
  if (syntax.initializer.isNotEmpty)
    bindings = bindExpressionLocals(
      feSources,
      syntax.initializer[0],
      feLocalFunctions,
    );
  while (feLocalOwners.length < feLocalFunctions.length)
    feLocalOwners.add(owner);
  return bindings;
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
  feClassStaticGlobals.clear();
  feMemberFunctions.clear();
  feClassFieldStarts.clear();
  feFieldNodes.clear();
  feFieldBindings.clear();
  feClassFieldCounts.clear();
  feClassConstructors.clear();
  feConstructorPlans.clear();
  feFieldTypes.clear();
  feFieldIndices.clear();
  feOwners.clear();
  feConstructors.clear();
  feFunctionNodes.clear();
  feLocalFunctions.clear();
  feLocalClosures.clear();
  feLocalConstants.clear();
  feLocalOwners.clear();
  feLocalStart = 0;
  feImplicitReceiverSlot = -1;
  feLocalInferred.clear();
  feLocalContexts.clear();
  feReturnTypes = null;
  exportNames.clear();
  exportFunctions.clear();
  exportParameters.clear();
  feNativeNames.clear();
  feNativeParams.clear();
  feInitializingGlobal = -1;
  feGlobalSources.clear();
  feGlobalOwners.clear();
  feGlobalNodes.clear();
  feRawGlobals.clear();
  feGlobalInitializers.clear();
  _feLiteralTypes.clear();
  _feLiteralValues.clear();
  feParamDefaults.clear();
  feConstantObjects.clear();
  feConstantGetters.clear();
  constantData.clear();
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
      null,
      null,
      false,
      0,
      false,
    ),
  );
  feParamDefaults.add(<ConstantValue>[]);
  feOwners.add(-1);
  feConstructors.add(0);
  feSources = source;
  entrySource = source.entry;
  entryFunction = -1;
  feSymbols = SymbolTable(source, <DeclarationSymbol>[]);
  feTokens = source.tokens;
  feAt = 0;
  feRuntimeTokens = source.runtimeTokens;
  var paths = <String>[for (var file in source.files) file.path];
  var syntax = parseUnit(Parser(feTokens, 0, 0, paths));
  feInstallSymbols();
  feCollectDeclarations(syntax);
  checkInitializers(feSymbols, syntax);
  var plannedFunction = 0;
  while (plannedFunction < functions.length) {
    var plan = const ConstructorPlan(<ConstructorStep>[], -1);
    if (feConstructors[plannedFunction] == 1) {
      var owner = feOwners[plannedFunction];
      plan = planConstructorInitializers(
        feSymbols,
        feClassNodes[owner],
        feFunctionNodes[plannedFunction],
        feMembers[owner],
        feClassConstructors[owner],
      );
    }
    feConstructorPlans.add(plan);
    plannedFunction++;
  }
  checkConstructorRedirects(feSymbols, feFunctionNodes, feConstructorPlans);
  var sourceFunctions = functions.length;
  var bodyBindings = <FunctionBindings>[];
  var bindingFunction = 0;
  while (bindingFunction < sourceFunctions) {
    bodyBindings.add(
      bindFunctionLocals(
        source,
        feFunctionNodes[bindingFunction],
        feHasReceiver(bindingFunction),
        feLocalFunctions,
        feOwners[bindingFunction] < 0
            ? null
            : feMembers[feOwners[bindingFunction]],
      ),
    );
    while (feLocalOwners.length < feLocalFunctions.length)
      feLocalOwners.add(feOwners[bindingFunction]);
    bindingFunction++;
  }
  feConstants = ConstantContext(feSymbols, feGlobalNodes, globalTypes);
  feConstants.classMembers = feMembers;
  feConstants.classConstructors = feClassConstructors;
  feConstants.classStaticGlobals = feClassStaticGlobals;
  feConstants.classFunctions = feMemberFunctions;
  feConstants.globalOwners = feGlobalOwners;
  feConstants.identical = symbolOwnDeclaration(
    feSymbols,
    sourceCore,
    'identical',
  );
  feRegisterConstantConstructors();
  feResolvePragma();
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
  var initializerBindings = <FunctionBindings>[];
  var initializer = 0;
  while (initializer < feGlobalNodes.length) {
    initializerBindings.add(
      feBindInitializer(
        feGlobalNodes[initializer],
        feGlobalOwners[initializer],
      ),
    );
    initializer++;
  }
  var owner = 0;
  while (owner < feClassNodes.length) {
    var field = feClassFieldStarts[owner];
    var end = field + feClassFieldCounts[owner];
    while (field < end) {
      feFieldBindings.add(feBindInitializer(feFieldNodes[field], owner));
      field++;
    }
    owner++;
  }
  feLocalStart = sourceFunctions;
  var local = 0;
  while (local < feLocalFunctions.length) {
    var declaration = feLocalFunctions[local];
    var function = feRegisterFunction(declaration.syntax, -1, false, true);
    for (var binding in declaration.body!.captures) {
      if (declaration.body!.variables[binding].function != local) {
        var info = functions[function];
        info.closureLayout = ClosureLayout(<int>[]);
        info.parameterTypes.insert(0, tFunction);
        info.parameters++;
        info.locals++;
        break;
      }
    }
    feLocalClosures.add(FeClosure());
    bodyBindings.add(declaration.body!);
    feLocalConstants.add(null);
    feLocalInferred.add(declaration.syntax.result.name != '');
    feLocalContexts.add(-1);
    local++;
  }
  sourceFunctions = functions.length;
  feResolveDefaults(feLocalStart);
  var sourceGlobals = globalNames.length;
  fePrepareGlobals(sourceGlobals, initializerBindings);
  var global = 0;
  while (global < sourceGlobals) {
    if (feGlobalInitializers[global].getter >= 0) feInferGlobal(global);
    global++;
  }
  feCheckAccessorVersions();
  feNextLocal = 0;
  feFunction = 0;
  var i = 0;
  while (i < sourceGlobals) {
    if (feGlobalInitializers[i].getter < 0 &&
        feGlobalNodes[i].modifier != 'const') {
      feInitializingGlobal = i;
      var type = feLowerInitializer(
        feGlobalNodes[i], feGlobalInitializers[i].bindings, globalTypes[i],
      );
      if (globalTypes[i] < 0) globalTypes[i] = type;
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
    functions[f].start = ir.length;
    feBeginFunction(f, bodyBindings[f]);
    var functionSyntax = feFunctionNodes[f];
    var expression = functionSyntax.arrow;
    if (feConstructors[f] == 1) {
      feLowerConstructor(f);
    } else if (expression != null) {
      if (feInfersLocalResult(f)) {
        var type = feLowerAssignedValue(expression, feLocalResultContext(f));
        feConvertValue(type, functions[f].result, expression.token);
      } else {
        feLowerInContext(expression, functions[f].result);
      }
      feEmit(opReturn);
    } else {
      var body = functionSyntax.body;
      if (body != null) feLowerStatement(body);
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
  feConstants.lexicalClass = -1;
  feGenerateGlobals(sourceGlobals);
  if (imageKind == 0)
    feGenerateEntry();
  else
    feGenerateConstantObjects();
  feGenerateCallableAdapters();
}

void feGenerateCallableAdapters() {
  var targets = functions.length;
  var target = 0;
  while (target < targets) {
    var info = functions[target];
    if (info.callableAdapter == -2) {
      var parameters = <int>[tFunction];
      var offset = info.closureLayout == null ? 0 : 1;
      var p = offset;
      while (p < info.parameterTypes.length) {
        parameters.add(tDynamic);
        p++;
      }
      var adapter = functions.length;
      info.callableAdapter = adapter;
      functions.add(
        FunctionInfo(
          '#call:' + info.name,
          ir.length,
          parameters.length,
          parameters.length,
          tDynamic,
          parameters,
          <int>[],
          info.source,
        ),
      );
      feFunction = adapter;
      feFlow = flowCreate(0);
      feSlotTypes = <int>[];
      feNextLocal = 0;
      p = 0;
      while (p < parameters.length) {
        feTemp(parameters[p]);
        p++;
      }
      var token = feFunctionNodes[target].token;
      if (offset != 0) {
        feOperand(opLoadLocal, 0);
        if (info.closureLayout!.boundReceiver) {
          feOperand(opInt, 2);
          feBuiltinTyped(bObjectGet, 2, info.parameterTypes[0]);
        }
      }
      p = offset;
      while (p < info.parameterTypes.length) {
        feOperand(opLoadLocal, p + 1 - offset);
        feConvertValue(tDynamic, info.parameterTypes[p], token);
        p++;
      }
      feCall(target, info.parameters);
      feCallableBox(info.result, token);
      feEmit(opReturn);
      functions[adapter].locals = feNextLocal;
      functions[adapter].localTypes = feSlotTypes;
    }
    target++;
  }
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
  var argumentsType = listType(tString);
  if (positional > 0 &&
      !typingAssignable(argumentsType, functions[main].parameterTypes[0]))
    feAstError(
      parameters[0].token,
      'first main parameter must accept List<String>',
    );
  var supplied = positional;
  if (supplied > 2) supplied = 2;
  p = supplied;
  while (p < parameters.length) {
    var value = feParamDefaults[main][p];
    if (typeIsList(value.kind) || typeIsClass(value.kind))
      feConstantGetter(value);
    p++;
  }
  feGenerateConstantObjects();
  entryFunction = main;
  if (parameters.length <= 1 && parameters.length == positional) return;
  var types = <int>[if (positional > 0) argumentsType];
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
      var expected = functions[main].parameterTypes[p];
      if (typeIsSubtype(actual, expected)) {
        feConvertValue(actual, expected, parameters[p].token);
      } else {
        feConvertValue(actual, tDynamic, parameters[p].token);
        feBuiltinTyped(bValueCast, 1, expected);
      }
    } else {
      feDefaultArgument(main, p, syntax.token);
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

void feLowerWhileFor(
  AstStatement statement,
  void Function(AstStatement) lowerBody,
) {
  var kind = statement.kind;
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
    lowerBody(statement.children[1]);
  else
    lowerBody(statement.children[0]);
  var update = ir.length;
  feContinueFlow(statement.token, continueBase);
  if (kind == astForStatement) {
    for (var variable in statement.children[0].variables) {
      if (feCellBinding(variable.binding)) {
        feLoadLocalStorage(variable.binding);
        feAllocateCell(feBindingTypes[variable.binding]);
        feOperand(opStoreLocal, feBindingSlots[variable.binding]);
      }
    }
  }
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
}

void feLowerForIn(
  AstStatement statement,
  void Function(AstStatement) lowerBody,
) {
  AstVariable? declaration;
  if (statement.variables.isNotEmpty) declaration = statement.variables[0];
  var context = -1;
  if (declaration != null) {
    feCheckMetadata(declaration.metadata, feLexicalOwner(feFunction));
    if (declaration.type.name != '')
      context = listType(resolveType(feSymbols, declaration.type));
  }
  var iterableType = feNonNullableValue(
    feLowerHint(statement.expressions[0], context),
    statement.expressions[0].token,
  );
  var element = typingIterableElement(iterableType, false);
  if (element < 0)
    feAstError(statement.token, 'for-in requires a compatible iterable');
  if (!typeIsList(iterableType))
    iterableType = feConvertValue(
      iterableType,
      listType(element),
      statement.token,
    );
  var iterable = feTemp(iterableType);
  feOperand(opStoreLocal, iterable);
  var length = feTemp(tInt);
  feOperand(opLoadLocal, iterable);
  feBuiltin(bListLength, 1);
  feOperand(opStoreLocal, length);
  var index = feTemp(tInt);
  feOperand(opInt, 0);
  feOperand(opStoreLocal, index);
  var type = element;
  if (context >= 0) type = typeArgument(context);
  var cell = declaration != null && feCellBinding(declaration.binding);
  var variable = -1;
  if (declaration != null) {
    variable = feTemp(cell ? tObject : type);
    feBindLocal(declaration.binding, type, variable);
  }
  feFlow = flowSplit(feFlow);
  feLoopFlow(statement);
  var exitFlow = flowCopy(feFlow);
  if (declaration != null) flowDeclare(feFlow, declaration.binding, type, true);
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
  feBuiltinTyped(bListGet, 2, element);
  if (declaration != null) {
    feConvertValue(
      feImplicitCall(element, type, statement.token),
      type,
      statement.token,
    );
    if (cell) feAllocateCell(type);
    feOperand(opStoreLocal, variable);
  } else {
    var value = feTemp(type);
    feOperand(opStoreLocal, value);
    var target = feLowerLvalue(statement.expressions[1], false);
    feOperand(opLoadLocal, value);
    var assigned = feImplicitCall(type, target.type, statement.token);
    feConvertValue(assigned, target.type, statement.token);
    feWriteLvalue(target, statement.token);
    feWriteFlow(target, assigned);
    feEmit(opPop);
  }
  var breakBase = feBreaks.length;
  var continueBase = feContinues.length;
  feLoopBreaks.add(breakBase);
  feLoopContinues.add(continueBase);
  lowerBody(statement.children[0]);
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

void fePatternRead(int slot, int type, int token) {
  feOperand(opLoadLocal, slot);
  var stored = feSlotTypes[slot];
  if (stored == tVoid && type != tVoid) {
    feBuiltinTyped(bBoxRef, 1, tDynamic);
    stored = tDynamic;
  }
  if (typeIsSubtype(stored, type))
    feConvertValue(stored, type, token);
  else
    feNarrowValue(stored, type);
}

int fePatternSlot(int slot, int type, int token) {
  if (feSlotTypes[slot] == type) return slot;
  fePatternRead(slot, type, token);
  var result = feTemp(type);
  feOperand(opStoreLocal, result);
  return result;
}

void fePatternVariables(CheckedPattern pattern) {
  var binding = pattern.syntax.binding;
  if (binding >= 0 && feBindingSlots[binding] < 0)
    feBindLocal(binding, pattern.variableType, feTemp(pattern.variableType));
  for (var child in pattern.children) fePatternVariables(child);
}

void feLowerPattern(CheckedPattern pattern, int value, List<int> failed) {
  var syntax = pattern.syntax;
  var kind = syntax.kind;
  var token = syntax.token;
  if (kind == patternVariable) {
    if (pattern.tested >= 0 && !typeIsSubtype(pattern.input, pattern.tested)) {
      fePatternRead(value, pattern.input, token);
      feCallableBox(pattern.input, token);
      feOperand(opTypeTest, pattern.tested);
      failed.add(feJump(opJumpFalse));
    }
    var binding = syntax.binding;
    if (binding >= 0) {
      fePatternRead(value, pattern.variableType, token);
      feOperand(opStoreLocal, feBindingSlots[binding]);
      flowDeclare(feFlow, binding, pattern.variableType, true);
    }
  } else if (kind == patternAnd) {
    var left = pattern.children[0];
    feLowerPattern(left, value, failed);
    var right = pattern.children[1];
    feLowerPattern(right, fePatternSlot(value, right.input, token), failed);
  } else if (kind == patternOr) {
    var before = flowCopy(feFlow);
    var other = <int>[];
    feLowerPattern(pattern.children[0], value, other);
    var leftFlow = feFlow;
    var done = feJump(opJump);
    fePatchJumps(other, ir.length);
    feFlow = before;
    var right = pattern.children[1];
    feLowerPattern(right, fePatternSlot(value, right.input, token), failed);
    feFlow = feJoinFlow(leftFlow, feFlow);
    fePatch(done, ir.length);
  } else if (kind == patternNullCheck) {
    failed.add(feJumpIfNull(value));
    var inner = pattern.children[0];
    feLowerPattern(inner, fePatternSlot(value, inner.input, token), failed);
  } else if (kind == patternCast || kind == patternNullAssert) {
    fePatternRead(value, pattern.input, token);
    feCallableBox(pattern.input, token);
    var checked = pattern.tested;
    if (kind == patternNullAssert && typeCanBeNull(checked)) checked = tObject;
    feOperand(opTypeCast, checked);
    feConvertValue(checked, pattern.tested, token);
    var slot = feTemp(pattern.tested);
    feOperand(opStoreLocal, slot);
    feLowerPattern(pattern.children[0], slot, failed);
  } else {
    var constant = pattern.constant!;
    var input = pattern.input;
    if (input == tVoid) input = tDynamic;
    var constantType = constant.type == tVoid ? tDynamic : constant.type;
    var comparison = tBool;
    if (kind == patternConstant) {
      feConstantValue(constant, constantType, token);
      fePatternRead(value, input, token);
      comparison = feCombine('==', constantType, input, token);
    } else {
      fePatternRead(value, input, token);
      feConstantValue(constant, constantType, token);
      comparison = feCombine(syntax.text, input, constantType, token);
    }
    feBooleanValue(comparison, token);
    failed.add(feJump(opJumpFalse));
  }
}

int feLowerSwitchExpression(AstExpression expression, int context) {
  var source = expression.children[0];
  var type = feLowerExpression(source);
  var value = feTemp(type);
  feOperand(opStoreLocal, value);
  feFlow = flowSplit(feFlow);
  var exitFlow = flowCopy(feFlow);
  flowUnreachable(exitFlow);
  var slots = <int>[];
  var conversions = <int>[];
  var result = tNever;
  var coverage = 0;
  var remaining = type;
  var binding = source.kind == astName ? source.binding : -1;
  if (binding >= 0 && !fePromotable(binding)) binding = -1;
  for (var arm in expression.arms) {
    feConstants.localTypes = feFlow.types;
    var pattern = checkPattern(
      feConstants,
      arm.pattern,
      remaining,
      feBindingTypes,
    );
    fePatternVariables(pattern);
    var nextFlow = flowCopy(feFlow);
    if (pattern.remaining == tNever) flowUnreachable(nextFlow);
    var failed = <int>[];
    feLowerPattern(
      pattern,
      fePatternSlot(value, remaining, arm.pattern.token),
      failed,
    );
    if (binding >= 0) flowPromote(feFlow, binding, pattern.matched);
    var guard = arm.guard;
    if (guard != null) {
      var rejected = feConditionJumps(guard, false, failed);
      nextFlow = feJoinFlow(nextFlow, rejected);
      if (binding >= 0) {
        var written = <int>[];
        collectWrittenExpression(
          guard,
          List<bool>.filled(feBindingTypes.length, false),
          written,
        );
        for (var changed in written) {
          if (changed == binding) binding = -1;
        }
      }
    } else {
      coverage |= pattern.coverage;
      if (pattern.remaining != tNever) remaining = pattern.remaining;
    }
    var armType = feLowerHint(arm.value, context);
    result = joinTypes(result, armType);
    var slot = feTemp(armType);
    feOperand(opStoreLocal, slot);
    slots.add(slot);
    conversions.add(feJump(opJump));
    exitFlow = feJoinFlow(exitFlow, feFlow);
    fePatchJumps(failed, ir.length);
    feFlow = nextFlow;
    if (binding >= 0) flowPromote(feFlow, binding, remaining);
  }
  var required = patternRequiredSpace(type);
  if ((coverage & required) != required)
    feAstError(expression.token, 'switch expression is not exhaustive');
  feCall(feFindFunction('rtPatternMatchFailure'), 0);
  feConvertValue(tNever, functions[feFunction].result, expression.token);
  feEmit(opReturn);
  var done = <int>[];
  for (var i = 0; i < slots.length; i++) {
    fePatch(conversions[i], ir.length);
    var slot = slots[i];
    feOperand(opLoadLocal, slot);
    feConvertValue(feSlotTypes[slot], result, expression.arms[i].value.token);
    done.add(feJump(opJump));
  }
  fePatchJumps(done, ir.length);
  if (slots.isEmpty) feInteger(0, tNever);
  feFlow = flowUnsplit(exitFlow);
  return result;
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
  if (fallback >= 0 ||
      booleans == 3 &&
          sourceVersionAtLeast(
            feSources,
            feTokens[statement.token].source,
            3,
            0,
          ))
    flowUnreachable(exitFlow);
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
