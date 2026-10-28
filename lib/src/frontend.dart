import 'ast.dart';
import 'binary64.dart';
import 'frontend/arguments.dart';
import 'frontend/classes.dart';
import 'frontend/generics.dart';
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
  bool caseLabel = false;
  List<int> breaks;
  List<int> continues;
  int repeat;
  List<FlowState> breakFlows = <FlowState>[];
  List<FlowState> continueFlows = <FlowState>[];
  final int finallyDepth = feFinalizers.length;

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

class PatternReadCache {
  final int parent;
  final String name;
  final int first;
  final int second;
  int uses = 1;
  int slot = -1;
  int ready = -1;

  PatternReadCache(this.parent, this.name, [this.first = -1, this.second = -1]);
}

class FeLateLocal {
  final int state;
  final int initializer;

  FeLateLocal(this.state, this.initializer);
}

class FeCatch {
  final int value;
  final int trace;

  FeCatch(this.value, this.trace);
}

List<FeCatch> feCatches = <FeCatch>[];

const int completionNormal = 0;
const int completionReturn = 1;
const int completionThrow = 2;
const int completionBreak = 3;
const int completionContinue = 4;

class FeCompletion {
  final int kind;
  final int target;
  final ControlLabel? label;
  FlowState flow;

  FeCompletion(this.kind, this.target, this.label, this.flow);
}

class FeFinally {
  final int breakDepth = feLoopBreaks.length;
  final int continueDepth = feLoopContinues.length;
  final int flowDepth = feFlow.reachability.length;
  final int tag;
  final int returned;
  final FeCatch caught;
  final List<FeCompletion> completions = <FeCompletion>[];
  final List<int> entries = <int>[];

  FeFinally(this.tag, this.returned, this.caught);
}

List<FeFinally> feFinalizers = <FeFinally>[];

class FeFunctionState {
  final List<int> code = ir;
  final List<int> types = irTypes;
  final int function = feFunction;
  final int token = feAt;
  final FunctionBindings bindings = feBindings;
  final List<int> bindingTypes = feBindingTypes;
  final List<int> bindingSlots = feBindingSlots;
  final List<FeLateLocal?> lateLocals = feLateLocals;
  final List<int> slots = feSlotTypes;
  final int nextLocal = feNextLocal;
  final int implicitReceiverSlot = feImplicitReceiverSlot;
  final FlowState flow = feFlow;
  final List<ConstantValue> constants = feConstants.locals;
  final List<int> constantTypes = feConstants.localTypes;
  final int constantScope = feConstants.lexicalClass;
  final List<int> constantTypeScope = feConstants.typeScope;
  final List<int> breaks = feBreaks;
  final List<int> continues = feContinues;
  final List<FlowState> breakFlows = feBreakFlows;
  final List<FlowState> continueFlows = feContinueFlows;
  final List<int> loopBreaks = feLoopBreaks;
  final List<int> loopContinues = feLoopContinues;
  final List<ControlLabel> labels = feLabels;
  final List<FeCatch> catches = feCatches;
  final List<FeFinally> finalizers = feFinalizers;
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
    feLateLocals = lateLocals;
    feSlotTypes = slots;
    feNextLocal = nextLocal;
    feImplicitReceiverSlot = implicitReceiverSlot;
    feFlow = flow;
    feConstants.locals = constants;
    feConstants.localTypes = constantTypes;
    feConstants.lexicalClass = constantScope;
    feConstants.typeScope = constantTypeScope;
    feBreaks = breaks;
    feContinues = continues;
    feBreakFlows = breakFlows;
    feContinueFlows = continueFlows;
    feLoopBreaks = loopBreaks;
    feLoopContinues = loopContinues;
    feLabels = labels;
    feCatches = catches;
    feFinalizers = finalizers;
    feReturnTypes = returns;
    feInitializingGlobal = initializingGlobal;
  }
}

List<ConstantObject> feConstantObjects = <ConstantObject>[];
List<int> feConstantGetters = <int>[];

late SourceProgram feSources;
List<Token> feTokens = <Token>[];
int feAt = 0;
late SymbolTable feSymbols;
late ConstantContext feConstants;
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
List<ClassMembers> feOwnMembers = <ClassMembers>[];
List<int> feClassOrder = <int>[];
List<bool> feClassPolymorphic = <bool>[];
ClassMembers feObjectMembers = ClassMembers(<MemberBinding>[]);
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
List<FeLateLocal?> feLateLocals = <FeLateLocal?>[];
FlowState feFlow = .create(0);
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
List<int> feLateFieldStates = <int>[];
List<int> feLateFieldGetters = <int>[];
List<int> feLateFieldSetters = <int>[];
List<int> feLateFunctionFields = <int>[];
List<int> feOwners = <int>[];
// 0 ordinary function, 1 generative constructor, 2 factory constructor.
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
    return feMembers[owner].members[index].field;
  feAstError(token, 'unknown instance field ' + classNames[owner] + '.' + name);
}

int feMethod(int owner, String name, bool getter, [int token = -1]) {
  var index = token < 0
      ? lookupMember(feMembers[owner], name)
      : feMemberIndex(owner, name, token);
  if (index < 0) return -1;
  var member = feMembers[owner].members[index];
  if (member.isStatic) return -1;
  var method = member.method;
  if (getter) method = member.getter;
  if (method < 0) return -1;
  return method;
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
  List<int> enclosingTypes = const <int>[],
]) {
  if (syntax.abbreviated &&
      !sourceVersionAtLeast(feSources, feTokens[syntax.token].source, 3, 13))
    feAstError(
      syntax.token,
      'abbreviated constructors require language version 3.13',
    );
  if (syntax.typeParameters.isNotEmpty && (local || syntax.external))
    feAstError(
      syntax.token,
      'generic local or external functions are not yet supported',
    );
  if (syntax.external) {
    final source = feTokens[syntax.token].source;
    final primitive = fePrimitive(syntax.name);
    if (feRuntimeTokens == 0 || source != 0 || primitive == 0) {
      feAstError(
        syntax.token,
        'unsupported external declaration ' + syntax.name,
      );
    }
    if (owner >= 0 ||
        syntax.getter ||
        syntax.parameters.length != nativeBuiltinArity(primitive)) {
      feAstError(syntax.token, 'invalid primitive signature ' + syntax.name);
    }
    feCheckPrimitiveType(syntax.result, nativeBuiltinResultType(primitive));
    var parameter = 0;
    while (parameter < syntax.parameters.length) {
      final syntaxParameter = syntax.parameters[parameter];
      if (syntaxParameter.fieldFormal ||
          syntaxParameter.superFormal ||
          syntaxParameter.kind != astRequiredPositional)
        feAstError(syntaxParameter.token, 'primitive parameters require int');
      feCheckPrimitiveType(
        syntaxParameter.type,
        nativeBuiltinInputType(primitive),
      );
      parameter++;
    }
    final symbol = symbolOwnDeclaration(feSymbols, source, syntax.name);
    feSymbols.declarations[symbol].kind = symbolBuiltin;
    feSymbols.declarations[symbol].target = primitive;
    return -1;
  }
  final id = functions.length;
  final typeParameters = resolveFunctionTypeParameters(feSymbols, syntax, id);
  final typeScope = local ? enclosingTypes : typeParameters;
  final types = <int>[];
  final source = feTokens[syntax.token].source;
  var name = syntax.name;
  var result = tDynamic;
  if (constructor)
    result = classType(owner);
  else if (syntax.result.name != '')
    result = resolveType(feSymbols, syntax.result, typeScope);
  else if (owner >= 0 &&
      !syntax.isStatic &&
      syntax.name == 'toString' &&
      !syntax.getter &&
      !syntax.setter)
    result = tString;
  if (owner >= 0) {
    if (!constructor) name = classNames[owner] + '.' + syntax.name;
    if (!syntax.isStatic && !syntax.factory) {
      types.add(classType(owner));
    }
  }
  if (typeParameters.isNotEmpty) types.add(listType(tObject));
  var p = 0;
  while (p < syntax.parameters.length) {
    final parameter = syntax.parameters[p];
    if (parameter.superFormal) {
      if (!constructor || syntax.factory)
        feAstError(
          parameter.token,
          'super parameter requires a generative constructor',
        );
      if (!sourceVersionAtLeast(feSources, source, 2, 17))
        feAstError(
          parameter.token,
          'super parameters require language version 2.17',
        );
    }
    var type = tDynamic;
    if (parameter.fieldFormal) {
      if (!constructor || syntax.factory)
        feAstError(
          parameter.token,
          'field-formal parameter requires a generative constructor',
        );
      final entry = feField(owner, parameter.name, parameter.token);
      type = feFieldTypes[entry];
      if (parameter.type.name != '') {
        type = resolveType(feSymbols, parameter.type, typeScope);
        if (!typeIsSubtype(type, feFieldTypes[entry])) {
          feAstError(
            parameter.token,
            'field-formal type must be a subtype of the field type',
          );
        }
      }
    } else if (parameter.type.name != '') {
      type = resolveType(feSymbols, parameter.type, typeScope);
    }
    types.add(type);
    p++;
  }
  final count = types.length;
  functions.add(
    FunctionInfo(name, 0, count, count, result, types, <int>[], source),
  );
  functions[id].typeParameters = typeParameters;
  if (typeParameters.isNotEmpty)
    functions[id].typeEnvironment = owner >= 0 && !syntax.isStatic ? 1 : 0;
  if (enclosingTypes.isNotEmpty)
    functions[id].closureLayout = ClosureLayout(
      <int>[listType(tObject)],
      false,
      enclosingTypes,
    );
  feParamDefaults.add(<ConstantValue>[]);
  feFunctionNodes.add(syntax);
  feOwners.add(owner);
  feLateFunctionFields.add(-1);
  if (constructor) {
    feConstructors.add(syntax.factory ? 2 : 1);
    feClassConstructors[owner].add(id);
  } else {
    feConstructors.add(0);
  }
  if (owner < 0 && !local) {
    final symbol = symbolOwnDeclaration(feSymbols, source, syntax.name);
    if (syntax.setter)
      feSymbols.declarations[symbol].setter = id;
    else
      feSymbols.declarations[symbol].target = id;
  }
  var callable =
      typeParameters.isEmpty &&
      !constructor &&
      !syntax.getter &&
      !syntax.setter;
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
    if ((syntax.hasPrimary || syntax.abbreviatedBody) &&
        !sourceVersionAtLeast(feSources, source, 3, 13))
      feAstError(
        syntax.token,
        'primary constructors and class semicolons require language version 3.13',
      );
    if (syntax.hasPrimary)
      for (final constructor in syntax.constructors)
        if (!constructor.primary &&
            !constructor.factory &&
            (constructor.initializers.isEmpty ||
                constructor.initializers[0].kind != astRedirectInitializer))
          feAstError(
            constructor.token,
            'a class with a primary constructor can only add redirecting generative constructors',
          );
    var owner = classNames.length;
    classType(owner);
    classNames.add(syntax.name);
    feClassSources.add(source);
    feClassNodes.add(syntax);
    feClassFieldCounts.add(0);
    feClassConstructors.add(<int>[]);
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
    feSymbols.declarations[symbol].writable = syntax.hasSetter;
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
  feClassOrder = resolveClassInterfaces(feSymbols, unit.classes);
  checkTypeAliasDeclarations(feSymbols);
  feClassPolymorphic = <bool>[
    for (final syntax in unit.classes) syntax.isAbstract,
  ];
  for (var owner = 0; owner < unit.classes.length; owner++)
    for (final method in unit.classes[owner].methods)
      if (!method.isStatic && method.body == null && method.arrow == null)
        feClassPolymorphic[owner] = true;
  for (final parents in classSupertypes)
    for (final parent in parents)
      if (typeIsClass(parent)) feClassPolymorphic[typeArgument(parent)] = true;
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
    for (final member in feMembers[i].members) {
      if (member.field >= 0) member.field += feClassFieldStarts[i];
      if (member.fieldSetter >= 0) member.fieldSetter += feClassFieldStarts[i];
    }
    var fields = unit.classes[i].fields;
    var field = 0;
    while (field < fields.length) {
      var syntax = fields[field];
      if (syntax.type.name == '' && syntax.declaringParameter == null)
        feAstError(syntax.token, 'field requires a type');
      var type = syntax.type.name == ''
          ? tDynamic
          : resolveType(feSymbols, syntax.type);
      feFieldNodes.add(syntax);
      feFieldTypes.add(type);
      feFieldIndices.add(field);
      feLateFieldStates.add(-1);
      feLateFieldGetters.add(-1);
      feLateFieldSetters.add(-1);
      field++;
    }
    feClassFieldCounts[i] = field;
    var storageFields = field;
    for (var index = 0; index < fields.length; index++) {
      if (fields[index].lateVariable) {
        feLateFieldStates[feClassFieldStarts[i] + index] = storageFields++;
      }
    }
    classSizes[i] = objectHeaderBytes + storageFields * 8;
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
    final globals = <int>[];
    var field = 0;
    while (field < fields.length) {
      globals.add(feRegisterGlobal(fields[field], i));
      field++;
    }
    for (final member in feMembers[i].members)
      if (member.staticField >= 0)
        member.staticField = globals[member.staticField];
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
    final methods = <int>[];
    var method = 0;
    while (method < syntax.methods.length) {
      methods.add(feRegisterFunction(syntax.methods[method], i, false));
      method++;
    }
    for (final member in feMembers[i].members) {
      if (member.method >= 0) member.method = methods[member.method];
      if (member.getter >= 0) member.getter = methods[member.getter];
      if (member.setter >= 0) member.setter = methods[member.setter];
    }
    for (var index = 0; index < syntax.fields.length; index++) {
      final field = feClassFieldStarts[i] + index;
      final variable = syntax.fields[index];
      if (!variable.lateVariable) continue;
      final getter = AstFunction(
        '#lateGet:' + variable.name,
        variable.type,
        const <AstParameter>[],
        null,
        variable.initializer.isEmpty ? null : variable.initializer[0],
        false,
        variable.token,
        true,
      );
      final get = feRegisterFunction(getter, i, false);
      feLateFunctionFields[get] = field;
      feLateFieldGetters[field] = get;
      if (variable.hasSetter) {
        final setter = AstFunction(
          '#lateSet:' + variable.name,
          variable.type,
          <AstParameter>[
            AstParameter(variable.type, '#value', false, variable.token),
          ],
          null,
          null,
          false,
          variable.token,
          true,
        );
        final set = feRegisterFunction(setter, i, false);
        feLateFunctionFields[set] = field;
        feLateFieldSetters[field] = set;
      }
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
      final syntax = feFunctionNodes[toString];
      if (syntax.body != null || syntax.arrow != null)
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
  if (owner < 0 && feRuntimeTokens > 0 && source == 0 && !syntax.lateVariable)
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
  return feOwners[function] >= 0 &&
      !feFunctionNodes[function].isStatic &&
      !feFunctionNodes[function].factory;
}

int feTypeEnvironmentSlot(int function) => functions[function].typeEnvironment;

int feParameterOffset(int function) {
  var offset =
      feHasReceiver(function) || functions[function].closureLayout != null
      ? 1
      : 0;
  if (functions[function].typeParameters.isNotEmpty) offset++;
  return offset;
}

int feResolveType(AstType syntax) =>
    resolveType(feSymbols, syntax, functions[feFunction].typeScope);

void feLoadCurrentTypeEnvironment() {
  if (functions[feFunction].typeParameters.isNotEmpty) {
    feOperand(opLoadLocal, feTypeEnvironmentSlot(feFunction));
  } else {
    feOperand(opLoadLocal, 0);
    feOperand(opInt, 2);
    feBuiltinTyped(bObjectGet, 2, listType(tObject));
  }
}

// Returns the template operand so inferred List literals can finish its type.
int feRuntimeType(int type, [bool instantiate = false]) {
  final position = ir.length;
  feOperand(opTypeReference, type);
  if (typeContainsParameters(type) || instantiate) {
    if (functions[feFunction].typeScope.isEmpty)
      feAstError(feAt, 'type has no runtime type environment');
    feLoadCurrentTypeEnvironment();
    feBuiltinTyped(bTypeInstantiate, 2, tObject);
  }
  return position + 1;
}

void feEmit(int op) {
  var type = tVoid;
  if (op >= opAdd && op <= opBitNot || op == opDoubleCompare) type = tInt;
  if (op >= opDoubleAdd && op <= opDoubleDiv ||
      op == opDoubleNeg ||
      op == opIntToDouble)
    type = tDouble;
  if (op >= opEq && op <= opGe || op == opNot) type = tBool;
  ir.add(op);
  irTypes.add(type);
}

void feWord(int value) {
  ir.add(value);
  irTypes.add(tVoid);
}

void feOperand(int op, int value) {
  if ((op == opTypeTest || op == opTypeCast) && typeContainsParameters(value)) {
    feRuntimeType(value);
    feBuiltinTyped(
      op == opTypeTest ? bValueIs : bValueCheck,
      2,
      op == opTypeTest ? tBool : value,
    );
    return;
  }
  var position = ir.length;
  feEmit(op);
  feWord(value);
  if (op == opInt || op == opMetadataAddress) irTypes[position] = tInt;
  if (op == opString) irTypes[position] = tString;
  if (op == opDouble) irTypes[position] = tDouble;
  if (op == opTypeReference) irTypes[position] = tObject;
  if (op == opDescriptor) irTypes[position] = tPointer;
  if (op == opConstantData) irTypes[position] = tPointer;
  if (op == opClosureDescriptor ||
      op == opCaptureCellDescriptor ||
      op == opLateCellDescriptor)
    irTypes[position] = tPointer;
  if (op == opTypeTest) irTypes[position] = tBool;
  if (op == opTypeCast) irTypes[position] = value;
  if (op == opLoadLocal) irTypes[position] = feSlotTypes[value];
  if (op == opLoadGlobal) irTypes[position] = globalTypes[value];
}

void feInteger(int value, int type) {
  feOperand(type == tDouble ? opDouble : opInt, value);
  irTypes[ir.length - 2] = type;
}

void feDuplicate(int type) {
  feEmit(opDup);
  irTypes[ir.length - 1] = type;
}

int feBuiltinType(int id) {
  if (id == bLateError) return tNever;
  if (id == bDoubleToString) return tString;
  if (id == bDoubleParse || id == bDoubleModulo || id == bValueToDouble)
    return tDouble;
  if (id == bDoubleToInt ||
      id == bDoubleTruncDiv ||
      id == bValueToInt ||
      id == bValueCompareTo)
    return tInt;
  if (id == bDoubleTryParse) return nullableType(tDouble);
  if (id == bNumberProperty) return tBool;
  if (id >= bNativeFloat64Add && id <= bNativeResumeContext)
    return nativeBuiltinResultType(id);
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
  if (id == bValueCast && typeContainsParameters(type)) {
    feRuntimeType(type);
    feBuiltinTyped(bValueCheck, 2, type);
    return;
  }
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
  return variable.captured &&
      (variable.written || variable.lateVariable) &&
      !variable.constant;
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
  if (promoted == tInt || promoted == tDouble || promoted == tBool)
    builtin = bValueCast;
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
  if (feFlow.assignments[binding] != flowAssigned &&
      (!variable.lateVariable ||
          feFlow.assignments[binding] == flowUnassigned &&
              !bindingDeclaration(feBindings, binding).writeCaptured)) {
    feAstError(
      token,
      'local is not definitely assigned: ' + feBindings.variables[binding].name,
    );
  }
  if (variable.lateVariable) feInitializeLateLocal(binding, token);
  var stored = feLoadLocalStorage(binding);
  var type = feFlow.types[binding];
  feNarrowValue(stored, type);
  return type;
}

int feLocalSlot(int binding, int token) {
  if (bindingDeclaration(feBindings, binding).unavailable)
    feAstError(token, 'pattern variable is not shared by every case');
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
  if (owner < 0 || feMemberIndex(owner, expression.text, expression.token) < 0)
    return false;
  var member = feMembers[owner]
      .members[feMemberIndex(owner, expression.text, expression.token)];
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
      .members[feMemberIndex(owner, expression.text, expression.token)]
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
  var head = prefix == '' ? name : prefix;
  if (typeParameterInScope(functions[feFunction].typeScope, head) >= 0)
    feAstError(token, 'type parameter values are not yet supported');
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
  if (typeParameterInScope(functions[feFunction].typeScope, prefix) >= 0)
    return false;
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
  if (expression.kind == astTypeReference) return expression.declaration;
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
      var index = feMemberIndex(owner, expression.text, expression.token);
      if (index >= 0 && feMembers[owner].members[index].isStatic) return owner;
    }
  } else if (expression.kind == astMember) {
    var receiver = expression.children[0];
    var symbol = feExpressionSymbol(receiver, false);
    var owner = declarationClassOwner(feSymbols, symbol);
    if (owner >= 0) {
      var index = feMemberIndex(owner, expression.text, expression.token);
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
  var index = feMemberIndex(owner, name, token);
  if (index < 0) feAstError(token, 'unknown static member ' + name);
  var member = feMembers[owner].members[index];
  if (!member.isStatic)
    feAstError(token, 'instance member requires a receiver');
  return member;
}

int feStaticReadType(MemberBinding member, int token) {
  if (member.getter >= 0) return functions[member.getter].result;
  if (member.staticField >= 0) return feGlobalType(member.staticField);
  feAstError(token, 'member has no getter: ' + member.name);
}

int feReadStaticMember(MemberBinding member, int token) {
  if (member.method >= 0) return feFunctionReference(member.method, token);
  final type = feStaticReadType(member, token);
  if (member.getter >= 0)
    feCall(member.getter, 0);
  else
    feLoadGlobalValue(member.staticField);
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
  } else if (_feLiteralTypes[global] == tDouble) {
    feOperand(opDouble, _feLiteralValues[global]);
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

int feMemberIndex(int owner, String name, int token) => lookupMember(
  feMembers[owner],
  name,
  sourceLibrary(feSources, feTokens[token].source),
);

void feCheckPrivate(int owner, String name, int token) {
  if (name.startsWith('_') &&
      feMemberIndex(owner, name, token) < 0 &&
      sourceLibrary(feSources, feTokens[token].source) !=
          sourceLibrary(feSources, feClassSources[owner])) {
    feAstError(token, 'private member ' + name);
  }
}

int fePrimitive(String name) {
  if (name == 'nativeCaptureContext') return bNativeCaptureContext;
  if (name == 'nativeResumeContext') return bNativeResumeContext;
  if (name == 'nativeExit') return bNativeExit;
  if (name == 'nativeValueBits') return bNativeValueBits;
  if (name == 'nativeValueFromBits') return bNativeValueFromBits;
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
  if (name == 'nativeFloat64Add') return bNativeFloat64Add;
  if (name == 'nativeFloat64Sub') return bNativeFloat64Sub;
  if (name == 'nativeFloat64Mul') return bNativeFloat64Mul;
  if (name == 'nativeFloat64Div') return bNativeFloat64Div;
  if (name == 'nativeFloat64Compare') return bNativeFloat64Compare;
  if (name == 'nativeFloat64FromInt') return bNativeFloat64FromInt;
  if (name == 'nativeFloat64ToInt') return bNativeFloat64ToInt;
  return 0;
}

void feCheckPrimitiveType(AstType syntax, int expected) {
  if (resolveType(feSymbols, syntax, const <int>[]) != expected)
    feAstError(syntax.token, 'invalid primitive value type');
}

void feInstallSymbols() {
  declareSymbol(
    feSymbols,
    sourceHost,
    'hostFloat64Add',
    symbolBuiltin,
    bNativeFloat64Add,
  );
  declareSymbol(
    feSymbols,
    sourceHost,
    'hostFloat64Sub',
    symbolBuiltin,
    bNativeFloat64Sub,
  );
  declareSymbol(
    feSymbols,
    sourceHost,
    'hostFloat64Mul',
    symbolBuiltin,
    bNativeFloat64Mul,
  );
  declareSymbol(
    feSymbols,
    sourceHost,
    'hostFloat64Div',
    symbolBuiltin,
    bNativeFloat64Div,
  );
  declareSymbol(
    feSymbols,
    sourceHost,
    'hostFloat64Compare',
    symbolBuiltin,
    bNativeFloat64Compare,
  );
  declareSymbol(
    feSymbols,
    sourceHost,
    'hostFloat64FromInt',
    symbolBuiltin,
    bNativeFloat64FromInt,
  );
  declareSymbol(
    feSymbols,
    sourceHost,
    'hostFloat64ToInt',
    symbolBuiltin,
    bNativeFloat64ToInt,
  );
  declareSymbol(feSymbols, sourceCore, 'int', symbolType, tInt);
  declareSymbol(feSymbols, sourceCore, 'double', symbolType, tDouble);
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
  CheckedMemberRead? directRead;

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
  '/' => bValueFloatDiv,
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
  if ((left == tInt || left == tDouble) &&
      (right == tInt || right == tDouble) &&
      (left == tDouble || right == tDouble || op == '/')) {
    if (left == tInt) {
      final saved = feTemp(right);
      feOperand(opStoreLocal, saved);
      feEmit(opIntToDouble);
      feOperand(opLoadLocal, saved);
    }
    if (right == tInt) feEmit(opIntToDouble);
    if (op == '%' || op == '~/') {
      feBuiltin(op == '%' ? bDoubleModulo : bDoubleTruncDiv, 2);
    } else if (op == '+' || op == '-' || op == '*' || op == '/') {
      feEmit(switch (op) {
        '+' => opDoubleAdd,
        '-' => opDoubleSub,
        '*' => opDoubleMul,
        _ => opDoubleDiv,
      });
    } else {
      feEmit(opDoubleCompare);
      if (op == '>=') {
        final comparison = feTemp(tInt);
        feOperand(opStoreLocal, comparison);
        feOperand(opLoadLocal, comparison);
        feOperand(opInt, 0);
        feEmit(opEq);
        feOperand(opLoadLocal, comparison);
        feOperand(opInt, 1);
        feEmit(opEq);
        feEmit(opOr);
        irTypes[ir.length - 1] = tBool;
      } else {
        feOperand(
          opInt,
          op == '<'
              ? -1
              : op == '>'
              ? 1
              : 0,
        );
        feEmit(
          op == '!='
              ? opNe
              : op == '<='
              ? opLe
              : opEq,
        );
      }
    }
    return result;
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
    else if (result == tInt || result == tDouble || result == tBool)
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
  if (actual != tNever &&
      typeIsTagged(actual) &&
      (expected == tInt || expected == tDouble || expected == tBool)) {
    feBuiltinTyped(bValueCast, 1, expected);
    return expected;
  }
  if (typeIsSubtype(actual, expected)) {
    var builtin = bBoxRef;
    if (typeIsTagged(expected)) {
      if (actual == tInt) builtin = bBoxInt;
      if (actual == tDouble) builtin = bBoxDouble;
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
  feBooleanValue(feLowerHint(expression, tBool), expression.token);
}

void feConditionFact(AstExpression expression, bool truth) {
  if (expression.kind == astBoolean) {
    if ((expression.text == 'true') != truth) flowUnreachable(feFlow);
  } else if (expression.kind == astTypeTest) {
    var binding = expression.children[0].binding;
    if (binding < 0 || !fePromotable(binding)) return;
    var tested = feResolveType(expression.typeArguments[0]);
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
  var after = FlowState.copy(feFlow);
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
  var bound = typeBound(type);
  if (bound != type) return feConvertValue(type, bound, token);
  return type;
}

int feLowerHint(AstExpression expression, int context) {
  if (expression.kind == astStaticShorthand)
    return feLowerHint(
      resolveStaticShorthand(feSymbols, expression, context),
      context,
    );
  if (doubleContext(context)) {
    if (expression.kind == astInteger || isNegatedIntegerLiteral(expression)) {
      feOperand(opDouble, decodeIntegerAsDouble(feSources, expression));
      return tDouble;
    }
  }
  if (expression.kind == astBinary &&
      expression.text != '&&' &&
      expression.text != '||' &&
      expression.text != '??') {
    final left = feLowerExpression(expression.children[0]);
    final right = feLowerHint(
      resolveEqualityShorthand(
        feSymbols,
        expression.text,
        expression.children[1],
        left,
      ),
      typingBinaryContext(expression.text, left, context),
    );
    return feCombine(expression.text, left, right, expression.token);
  }
  if (expression.kind == astPatternAssignment)
    return feLowerPatternAssignment(expression);
  if (context == schemaHole) context = -1;
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
  if (expression.kind == astCall) return feLowerCall(expression, context);
  var type = -1;
  var listContext = context;
  if (listContext >= 0) listContext = typeNonNullable(listContext);
  if (listContext >= 0 && typeIsList(listContext)) {
    if (expression.kind == astList) type = feLowerList(expression, listContext);
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
  if (name >= 0 && members.members[name].field >= 0)
    fePragmaNameField =
        members.members[name].field - feClassFieldStarts[fePragmaClass];
  if (options >= 0 && members.members[options].field >= 0)
    fePragmaOptionsField =
        members.members[options].field - feClassFieldStarts[fePragmaClass];
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

void feRegisterConstructorConstants() {
  for (var function = 1; function < feFunctionNodes.length; function++) {
    if (feConstructors[function] == 0) continue;
    final owner = feOwners[function];
    final syntax = feFunctionNodes[function];
    final fields = <int>[];
    final parameterTypes = <int>[];
    final fieldStart = feClassFieldStarts[owner];
    if (syntax.constant && !syntax.factory)
      for (var field = 0; field < feClassFieldCounts[owner]; field++)
        fields.add(feFieldTypes[fieldStart + field]);
    for (var p = 0; p < syntax.parameters.length; p++)
      parameterTypes.add(
        functions[function].parameterTypes[feParameterOffset(function) + p],
      );
    while (feConstants.constructors.length <= function)
      feConstants.constructors.add(null);
    feConstants.constructors[function] = ConstructorConstants(
      owner,
      feClassNodes[owner],
      syntax,
      fields,
      parameterTypes,
      feConstructorPlans[function],
    );
  }
  checkConstantConstructors(feConstants);
}

void feResolveFunctionDefaults(int f) {
  final owner = feLexicalOwner(f);
  final scope = feConstants.lexicalClass;
  final omitted = ConstantValue(tNull, tNull, 0, '');
  feConstants.localTypes = feFlow.types;
  final syntax = feFunctionNodes[f];
  feCheckMetadata(syntax.metadata, owner, f);
  final typeScope = feConstants.typeScope;
  feConstants.typeScope = functions[f].typeScope;
  for (var parameter in syntax.typeParameters)
    feCheckMetadata(parameter.metadata, owner);
  feConstants.lexicalClass = owner;
  final parameters = syntax.parameters;
  final offset = feParameterOffset(f);
  if (feParamDefaults[f].isEmpty)
    feParamDefaults[f] = List<ConstantValue>.filled(
      functions[f].parameters,
      omitted,
    );
  var p = 0;
  while (p < parameters.length) {
    final parameter = parameters[p];
    feCheckMetadata(parameter.metadata, owner);
    checkParameterName(feSources, parameters, p);
    if (parameter.kind != astRequiredPositional &&
        !parameter.required &&
        syntax.factoryRedirect == null) {
      var value = omitted;
      final type = functions[f].parameterTypes[offset + p];
      final expression = parameter.defaultValue;
      if (feConstructors[f] != 0)
        value = constructorParameterDefault(feConstants, f, p);
      else if (expression != null)
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
  feConstants.typeScope = typeScope;
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
            read = globalTypes[member.staticField];
          else if (member.field >= 0)
            read = feFieldTypes[member.field];
          else if (member.getter >= 0)
            read = functions[member.getter].result;
          if (read >= 0)
            feCheckLegacyAccessor(read, member.setter, member.isStatic ? 0 : 1);
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
    if (child.kind == tDouble) kind = typeKindDouble;
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
  else if (value.kind == tDouble)
    feOperand(opDouble, value.integer);
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
    functions[object.getter].end = ir.length;
    i++;
  }
}

void feLoadTypeEnvironment(List<int> arguments) {
  var environmentType = listType(tObject);
  var environment = feTemp(environmentType);
  feBuiltinTyped(bListNew, 0, environmentType);
  feOperand(opStoreLocal, environment);
  for (var argument in arguments) {
    feOperand(opLoadLocal, environment);
    feRuntimeType(argument);
    feBuiltin(bListAdd, 2);
    feEmit(opPop);
  }
  feOperand(opLoadLocal, environment);
}

int fePrepareInferredArguments(
  AstExpression call,
  int function,
  int context,
  bool suppliedOnly,
) {
  var info = functions[function];
  var parameters = info.typeParameters;
  var lower = List<int>.filled(parameters.length, -1);
  var upper = List<int>.filled(parameters.length, -1);
  if (context >= 0 && context != tDynamic && context != tVoid)
    constrainGenericTypes(
      info.result,
      context,
      parameters,
      lower,
      upper,
      false,
    );
  var fixed = <int>[];
  var schemaArguments = <int>[];
  for (var i = 0; i < parameters.length; i++) {
    var type = upper[i] >= 0 ? upper[i] : lower[i];
    var bound = typeParameterInfo(parameters[i]).bound;
    if (type >= 0 && !typeContainsParameters(bound))
      type = meetTypes(type, bound);
    fixed.add(type >= 0 && !typeHasSchemaHole(type) ? type : -1);
    schemaArguments.add(type < 0 ? typeSchemaHole() : type);
  }
  var syntax = feFunctionNodes[function];
  var offset = feParameterOffset(function);
  var bindings = bindArguments(feSources, syntax, call, 1);
  var actualTypes = <int>[];
  var actualSlots = <int>[];
  var checks = <int>[];
  var continuations = <int>[];
  for (var i = 1; i < call.children.length; i++) {
    var expression = call.children[i];
    if (expression.kind == astNamedArgument)
      expression = expression.children[0];
    var template = info.parameterTypes[offset + bindings[i - 1]];
    var schema = substituteType(template, parameters, schemaArguments);
    var closure = expression.function;
    if (closure != null && typeIsFunction(schema)) {
      var inputs = functionSignature(schema).parameters;
      for (var p = 0; p < closure.parameters.length && p < inputs.length; p++) {
        if (closure.parameters[p].type.name == '' &&
            typeHasSchemaHole(inputs[p]))
          feAstError(
            closure.parameters[p].token,
            'generic inference for untyped callback parameters is not yet supported',
          );
      }
    }
    var actual = feLowerHint(expression, schema);
    if (actual == tDynamic &&
        typeHasSchemaHole(schema) &&
        !typeIsParameter(template))
      feAstError(
        expression.token,
        'generic inference from dynamic compound arguments is not yet supported',
      );
    constrainGenericTypes(template, actual, parameters, lower, upper);
    var slot = feTemp(actual);
    feOperand(opStoreLocal, slot);
    actualTypes.add(actual);
    actualSlots.add(slot);
    // The inferred check still executes before the next source argument.
    checks.add(feJump(opJump));
    continuations.add(ir.length);
  }
  var arguments = inferGenericArguments(parameters, lower, upper, fixed);
  for (var i = 0; i < arguments.length; i++) {
    var bound = substituteType(
      typeParameterInfo(parameters[i]).bound,
      parameters,
      arguments,
    );
    if (!typeIsSubtype(arguments[i], bound))
      feAstError(
        call.token,
        'inferred type argument does not satisfy function bound',
      );
  }
  var invocation = genericCalls.length;
  genericCalls.add(GenericCall(function, arguments));
  var values = List<int>.filled(syntax.parameters.length, -1);
  var ready = feJump(opJump);
  for (var i = 0; i < actualSlots.length; i++) {
    fePatch(checks[i], ir.length);
    var declared = info.parameterTypes[offset + bindings[i]];
    var expected = substituteType(declared, parameters, arguments);
    var token = call.children[i + 1].token;
    feOperand(opLoadLocal, actualSlots[i]);
    feConvertValue(actualTypes[i], expected, token);
    var boundary = genericBoundaryType(declared);
    if (expected == tVoid && boundary == tDynamic)
      feBuiltinTyped(bBoxRef, 1, boundary);
    else
      feConvertValue(expected, boundary, token);
    var slot = feTemp(boundary);
    feOperand(opStoreLocal, slot);
    values[bindings[i]] = slot;
    feOperand(opJump, continuations[i]);
  }
  fePatch(ready, ir.length);
  feLoadTypeEnvironment(arguments);
  for (var i = 0; i < values.length; i++) {
    if (values[i] >= 0) {
      feOperand(opLoadLocal, values[i]);
    } else if (!suppliedOnly) {
      var declared = info.parameterTypes[offset + i];
      var expected = substituteType(declared, parameters, arguments);
      feConstantValue(
        feParamDefaults[function][offset + i],
        expected,
        call.token,
      );
      feConvertValue(expected, genericBoundaryType(declared), call.token);
    }
  }
  return invocation;
}

int fePrepareGenericArguments(
  AstExpression call,
  int function, [
  int context = -1,
  bool suppliedOnly = false,
]) {
  if (call.typeArguments.isEmpty)
    return fePrepareInferredArguments(call, function, context, suppliedOnly);
  var info = functions[function];
  if (call.typeArguments.length != info.typeParameters.length)
    feAstError(call.token, 'generic type argument count');
  var arguments = <int>[];
  for (var syntax in call.typeArguments) arguments.add(feResolveType(syntax));
  for (var i = 0; i < arguments.length; i++) {
    var bound = substituteType(
      typeParameterInfo(info.typeParameters[i]).bound,
      info.typeParameters,
      arguments,
    );
    if (!typeIsSubtype(arguments[i], bound))
      feAstError(
        call.typeArguments[i].token,
        'type argument does not satisfy function bound',
      );
  }
  var invocation = genericCalls.length;
  genericCalls.add(GenericCall(function, arguments));
  feLoadTypeEnvironment(arguments);
  var parameters = feFunctionNodes[function].parameters;
  var offset = feParameterOffset(function);
  var bindings = bindArguments(feSources, feFunctionNodes[function], call, 1);
  var values = List<int>.filled(parameters.length, -1);
  for (var i = 1; i < call.children.length; i++) {
    var expression = call.children[i];
    if (expression.kind == astNamedArgument)
      expression = expression.children[0];
    var parameter = bindings[i - 1];
    var declared = info.parameterTypes[offset + parameter];
    var type = substituteType(declared, info.typeParameters, arguments);
    var actual = feLowerInContext(expression, type);
    var boundary = genericBoundaryType(declared);
    if (actual == tVoid && boundary == tDynamic)
      feBuiltinTyped(bBoxRef, 1, boundary);
    else
      feConvertValue(actual, boundary, expression.token);
    var slot = feTemp(boundary);
    feOperand(opStoreLocal, slot);
    values[parameter] = slot;
  }
  for (var i = 0; i < parameters.length; i++) {
    if (values[i] >= 0) {
      feOperand(opLoadLocal, values[i]);
    } else if (!suppliedOnly) {
      var declared = info.parameterTypes[offset + i];
      var type = substituteType(declared, info.typeParameters, arguments);
      feConstantValue(feParamDefaults[function][offset + i], type, call.token);
      feConvertValue(type, genericBoundaryType(declared), call.token);
    }
  }
  return invocation;
}

int feFinishGenericCall(int invocation, int token) {
  var call = genericCalls[invocation];
  var info = functions[call.function];
  var boundary = genericBoundaryType(info.result);
  feEmit(opGenericCall);
  irTypes[ir.length - 1] = boundary;
  feWord(invocation);
  feWord(info.parameters);
  var result = substituteType(
    info.result,
    info.typeParameters,
    call.typeArguments,
  );
  if (boundary != result) {
    if (typingAssignable(boundary, result)) {
      feConvertValue(boundary, result, token);
    } else {
      feConvertValue(boundary, tDynamic, token);
      feOperand(opTypeCast, result);
    }
  }
  if (result == tNever) flowUnreachable(feFlow);
  return result;
}

int feInvokeDeclaration(
  AstExpression call,
  int function, [
  int receiver = 0,
  int context = -1,
  bool direct = false,
]) {
  final owner = receiver == 0 ? -1 : feOwners[function];
  final dispatch = !direct && owner >= 0 && feNeedsDispatch(owner)
      ? feDispatchMethod(function, call)
      : -1;
  if (functions[function].typeParameters.isNotEmpty) {
    final invocation = fePrepareGenericArguments(
      call,
      function,
      context,
      dispatch >= 0,
    );
    if (dispatch >= 0)
      genericCalls[invocation] = GenericCall(
        dispatch,
        genericCalls[invocation].typeArguments,
      );
    return feFinishGenericCall(invocation, call.token);
  }
  var count = feLowerArguments(call, 1, function, dispatch >= 0);
  feCall(dispatch >= 0 ? dispatch : function, count + receiver);
  return functions[function].result;
}

int feLowerArguments(
  AstExpression call,
  int start,
  int function, [
  bool suppliedOnly = false,
  int parameterStart = 0,
]) {
  if (call.typeArguments.length != 0)
    feAstError(call.token, 'nongeneric call does not accept type arguments');
  var parameters = feFunctionNodes[function].parameters;
  if (parameterStart != 0) parameters = parameters.sublist(parameterStart);
  var offset = feParameterOffset(function) + parameterStart;
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
    parameterStart,
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
    else if (!suppliedOnly)
      feDefaultArgument(function, offset + parameter, call.token);
    parameter++;
  }
  return suppliedOnly ? bindings.length : parameters.length;
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
    element = feResolveType(expression.typeArguments[0]);
  else if (context >= 0 && typeIsList(context))
    element = typeArgument(context);
  var type = listType(
    element < 0 ? tDynamic : typeCompleteSchema(element, tDynamic),
  );
  var runtimeType = -1;
  if (functions[feFunction].typeScope.isNotEmpty)
    runtimeType = feRuntimeType(type, true);
  var allocation = ir.length;
  feBuiltinTyped(
    runtimeType < 0 ? bListNew : bListNewTyped,
    runtimeType < 0 ? 0 : 1,
    type,
  );
  var literal = FeListLiteral(element, feTemp(type));
  feOperand(opStoreLocal, literal.slot);
  for (var child in expression.children) feLowerListElement(child, literal);
  if (element < 0)
    element = literal.inferred;
  else
    element = typeCompleteSchema(element, literal.inferred);
  if (element < 0) element = tDynamic;
  type = listType(element);
  // Resolve the allocation and its local before the stack IR enters SSA.
  irTypes[allocation] = type;
  if (runtimeType >= 0) ir[runtimeType] = type;
  feSlotTypes[literal.slot] = type;
  feOperand(opLoadLocal, literal.slot);
  return type;
}

void feAppendListElement(FeListLiteral literal, int type, int token) {
  literal.inferred = joinTypes(literal.inferred, type);
  if (literal.context >= 0)
    type = feConvertValue(
      type,
      typeCompleteSchema(literal.context, type),
      token,
    );
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
    var falseFlow = feIfConditionJumps(expression.children[0], otherwise);
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
    // Filtering null does not promote the source or terminate the skipped path.
    final afterValue = feFlow;
    feFlow = .copy(afterValue);
    var element = typingNonNull(type);
    feOperand(opLoadLocal, value);
    feNarrowValue(type, element);
    feAppendListElement(literal, element, source.token);
    fePatch(skip, ir.length);
    feFlow = afterValue;
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
  final emptyOrFinished = feFlow;
  feFlow = .copy(emptyOrFinished);
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
  feFlow = emptyOrFinished;
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
        metadataStrings |
        metadataLists |
        metadataValues |
        metadataRoots |
        metadataFrames |
        metadataHandlers;
    if (mask < 1 || (mask & ~allowed) != 0)
      feAstError(call.token, 'unknown metadata feature mask');
    feOperand(opMetadataAddress, mask);
    return tInt;
  }
  if (builtin == bPrintInt) {
    if (call.children.length != 2)
      feAstError(call.token, 'argument count for print');
    var type = feLowerHint(call.children[1], nullableType(tObject));
    if (type == tString)
      feBuiltin(bPrintString, 1);
    else if (type == tBool)
      feBuiltin(bPrintBool, 1);
    else if (type == tInt)
      feBuiltin(bPrintInt, 1);
    else if (type == tDouble) {
      feBuiltin(bDoubleToString, 1);
      feBuiltin(bPrintString, 1);
    } else {
      feConvertValue(type, tDynamic, call.token);
      feBuiltinTyped(bValueToString, 1, tString);
      feBuiltin(bPrintString, 1);
    }
    return tVoid;
  }
  var expected = nativeBuiltinArity(builtin);
  var count = call.children.length - 1;
  if (expected >= 0) {
    if (count != expected) feAstError(call.token, 'primitive argument count');
    var argument = 1;
    while (argument < call.children.length) {
      var expression = call.children[argument];
      if (expression.kind == astNamedArgument)
        feAstError(expression.token, 'primitive arguments must be positional');
      feLowerInContext(expression, nativeBuiltinInputType(builtin));
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
    final listContext = context < 0 ? -1 : typeNonNullable(context);
    if (receiver.typeArguments.length != 0) {
      if (receiver.typeArguments.length != 1)
        feAstError(receiver.token, 'List requires one type argument');
      element = feResolveType(receiver.typeArguments[0]);
    } else if (listContext >= 0 && typeIsList(listContext)) {
      element = typeArgument(listContext);
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
        valueType = feLowerAssignedValue(expression, element);
        if (element >= 0) {
          element = typeCompleteSchema(element, valueType);
          valueType = feConvertValue(valueType, element, expression.token);
        }
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
    if (typeContainsParameters(element < 0 ? valueType : element))
      feConvertValue(valueType, tDynamic, call.token);
    if (growableSlot >= 0)
      feOperand(opLoadLocal, growableSlot);
    else
      feInteger(0, tBool);
    if (element < 0) element = valueType;
    var type = listType(element);
    if (typeContainsParameters(type)) {
      feRuntimeType(type);
      feBuiltinTyped(bListFilledTyped, 4, type);
    } else {
      feBuiltinTyped(bListFilled, 3, type);
    }
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
  if (declaration.source == sourceCore &&
      name == 'double' &&
      (member == 'parse' || member == 'tryParse')) {
    if (call.text == astCallNew)
      feAstError(call.token, 'new cannot invoke a static method');
    if (call.typeArguments.isNotEmpty ||
        call.children.length != 2 ||
        call.children[1].kind == astNamedArgument)
      feAstError(call.token, 'double parsing requires one positional String');
    feLowerInContext(call.children[1], tString);
    final builtin = member == 'parse' ? bDoubleParse : bDoubleTryParse;
    feBuiltin(builtin, 1);
    return feBuiltinType(builtin);
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

int feLowerValueCall(AstExpression call, int type, [int context = -1]) {
  var bound = typeBound(type);
  if (bound != type) type = feConvertValue(type, bound, call.token);
  if (feClassType(type)) {
    var method = feMethod(typeArgument(type), 'call', false);
    if (method >= 0) {
      return feInvokeDeclaration(call, method, 1, context);
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

int feLowerMemberValueCall(
  AstExpression call,
  int type,
  String member, [
  int context = -1,
]) {
  var receiver = feTemp(type);
  feOperand(opStoreLocal, receiver);
  var owner = typeArgument(type);
  var binding =
      feMembers[owner].members[feMemberIndex(owner, member, call.token)];
  var value = -1;
  if (binding.getter >= 0)
    value = functions[binding.getter].result;
  else if (binding.field >= 0)
    value = feFieldTypes[binding.field];
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
      var invocation = -1;
      var count = 0;
      if (functions[method].typeParameters.isNotEmpty) {
        invocation = fePrepareGenericArguments(call, method, context);
        count = functions[method].parameters - 1;
      } else {
        count = feLowerArguments(call, 1, method);
      }
      var arguments = List<int>.filled(count, -1);
      var i = count - 1;
      while (i >= 0) {
        arguments[i] = feTemp(
          genericBoundaryType(functions[method].parameterTypes[i + 1]),
        );
        feOperand(opStoreLocal, arguments[i]);
        i--;
      }
      feOperand(opLoadLocal, receiver);
      feReadBoundMember(owner, binding, call.token);
      for (var argument in arguments) feOperand(opLoadLocal, argument);
      if (invocation >= 0) return feFinishGenericCall(invocation, call.token);
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
  MemberBinding member, [
  int context = -1,
]) {
  if (call.text == astCallNew)
    feAstError(call.token, 'new requires a constructor');
  if (member.method >= 0) {
    return feInvokeDeclaration(call, member.method, 0, context);
  }
  final type = feReadStaticMember(member, call.token);
  if (type == tNever) return feLowerNeverArguments(call);
  return feLowerValueCall(call, type, context);
}

int feLowerListSublist(AstExpression call, int type) {
  if (call.children.length < 2 || call.children.length > 3)
    feAstError(call.token, 'argument count for List.sublist');
  var receiver = feTemp(type);
  feOperand(opStoreLocal, receiver);
  feLowerInContext(call.children[1], tInt);
  var start = feTemp(tInt);
  feOperand(opStoreLocal, start);
  var end = feTemp(tInt);
  var hasEnd = feTemp(tInt);
  var done = -1;
  var absent = -1;
  if (call.children.length == 3) {
    var optional = nullableType(tInt);
    feLowerInContext(call.children[2], optional);
    var slot = feTemp(optional);
    feOperand(opStoreLocal, slot);
    absent = feJumpIfNull(slot);
    fePatternRead(slot, tInt, call.token);
    feOperand(opStoreLocal, end);
    feOperand(opInt, 1);
    feOperand(opStoreLocal, hasEnd);
    done = feJump(opJump);
    fePatch(absent, ir.length);
  }
  feOperand(opInt, 0);
  feOperand(opStoreLocal, end);
  feOperand(opInt, 0);
  feOperand(opStoreLocal, hasEnd);
  if (done >= 0) fePatch(done, ir.length);
  feOperand(opLoadLocal, receiver);
  feOperand(opLoadLocal, start);
  feOperand(opLoadLocal, end);
  feOperand(opLoadLocal, hasEnd);
  feBuiltinTyped(bListSublist, 4, type);
  return type;
}

bool feIsSuper(AstExpression expression) =>
    expression.kind == astName && expression.text == 'super';

int feSuperOwner(AstExpression receiver) {
  final owner = feLexicalOwner(feFunction);
  if (owner < 0 || receiver.binding < 0 || feBindings.receiver < 0)
    feAstError(receiver.token, 'super requires an instance receiver');
  final type = classSuperclasses[owner];
  return typeIsClass(type) ? typeArgument(type) : -1;
}

int feLoadSuper(AstExpression receiver, int owner) {
  final type = owner < 0 ? tObject : classType(owner);
  final actual = feReadLocal(receiver.binding, receiver.token);
  return feConvertValue(actual, type, receiver.token);
}

MemberBinding? feSuperImplementation(
  int owner,
  String name,
  int role,
  int token,
) => classImplementation(
  owner,
  name,
  sourceLibrary(feSources, feTokens[token].source),
  role,
  feOwnMembers,
  feObjectMembers,
  feFunctionNodes,
);

CheckedMemberRead feSuperRead(int owner, String name, int token) {
  final method = feSuperImplementation(owner, name, classMethod, token);
  final member =
      method ?? feSuperImplementation(owner, name, classGetter, token);
  if (member == null)
    feAstError(token, 'super member has no concrete getter: ' + name);
  if (member.receiverParameter)
    feAstError(token, 'Object method tear-offs are not yet supported');
  return feCheckBoundMember(owner, member, token, true);
}

int feLowerSuperCall(
  AstExpression call,
  AstExpression receiver,
  String name,
  int context,
) {
  final owner = feSuperOwner(receiver);
  final type = feLoadSuper(receiver, owner);
  final member = feSuperImplementation(owner, name, classMethod, call.token);
  if (member == null) {
    final read = feReadCheckedMember(
      feSuperRead(owner, name, call.token),
      call.token,
      true,
    );
    return feLowerValueCall(call, read, context);
  }
  final function = member.method;
  feConvertValue(type, functions[function].parameterTypes[0], call.token);
  if (member.receiverParameter) {
    final count = feLowerArguments(call, 1, function, false, 1);
    feCall(function, count + 1);
    return functions[function].result;
  }
  return feInvokeDeclaration(call, function, 1, context, true);
}

int feLowerMemberCall(
  AstExpression call,
  AstExpression callee, [
  int context = -1,
]) {
  var receiver = callee.children[0];
  var member = callee.text;
  if (feIsSuper(receiver))
    return feLowerSuperCall(call, receiver, member, context);
  if (receiver.kind == astFunctionExpression && member == 'call')
    return feLowerImmediateCall(call, receiver);
  var type = feLowerExpression(receiver);
  if (type == tNever) return feLowerNeverArguments(call);
  if (typeIsFunction(type) && member == 'call')
    return feLowerValueCall(call, type, context);
  if (member == 'toString' &&
      (!feClassType(type) || feMethod(typeArgument(type), member, false) < 0)) {
    if (call.typeArguments.length != 0)
      feAstError(call.token, 'nongeneric call does not accept type arguments');
    if (call.children.length != 1)
      feAstError(call.token, 'argument count for toString');
    if (type == tInt)
      feBuiltin(bIntToString, 1);
    else if (type == tDouble)
      feBuiltin(bDoubleToString, 1);
    else if (type != tString) {
      feConvertValue(type, tDynamic, call.token);
      feBuiltinTyped(bValueToString, 1, tString);
    }
    return tString;
  }
  type = feNonNullableValue(type, receiver.token);
  if ((type == tInt || type == tDouble || type == tNum || type == tDynamic) &&
      (member == 'toDouble' ||
          member == 'toInt' ||
          member == 'truncate' ||
          member == 'remainder' ||
          member == 'compareTo')) {
    final binary = member == 'remainder' || member == 'compareTo';
    if (call.typeArguments.isNotEmpty ||
        call.children.length != (binary ? 2 : 1) ||
        binary && call.children[1].kind == astNamedArgument)
      feAstError(call.token, 'invalid numeric method arguments');
    if (!binary && (type == tInt || type == tDouble)) {
      if (member == 'toDouble') {
        if (type == tInt) feEmit(opIntToDouble);
        return tDouble;
      }
      if (type == tDouble) feBuiltin(bDoubleToInt, 1);
      return tInt;
    }
    feConvertValue(type, tDynamic, call.token);
    var argumentType = -1;
    if (binary) {
      final hint = member == 'remainder'
          ? typingBinaryContext('%', type, context)
          : type == tDynamic
          ? -1
          : tNum;
      argumentType = feLowerHint(call.children[1], hint);
      if (type != tDynamic && !typingAssignable(argumentType, tNum))
        feAstError(call.children[1].token, 'numeric method requires num');
      feConvertValue(argumentType, tDynamic, call.token);
    }
    final builtin = switch (member) {
      'toDouble' => bValueToDouble,
      'toInt' || 'truncate' => bValueToInt,
      'compareTo' => bValueCompareTo,
      _ => bValueRemainder,
    };
    var result = feBuiltinType(builtin);
    if (member == 'remainder') result = tDynamic;
    feBuiltinTyped(builtin, binary ? 2 : 1, result);
    if (member == 'remainder' && type != tDynamic) {
      final expected = typingBinary('%', type, argumentType);
      return feConvertValue(result, expected, call.token);
    }
    if (type == tDynamic) return feConvertValue(result, tDynamic, call.token);
    return result;
  }
  if (feClassType(type)) {
    var owner = typeArgument(type);
    feCheckPrivate(owner, member, call.token);
    var function = feMethod(owner, member, false, call.token);
    if (function < 0) {
      if (call.text != astCallValue) {
        var index = feMemberIndex(owner, member, call.token);
        if (index < 0) feAstError(call.token, 'unknown member ' + member);
        var binding = feMembers[owner].members[index];
        if (binding.isStatic)
          feAstError(
            call.token,
            'static member cannot be accessed through an instance',
          );
        return feLowerMemberValueCall(call, type, member, context);
      }
      var value = feReadMember(type, member, call.token);
      if (value == tNever) return feLowerNeverArguments(call);
      return feLowerValueCall(call, value, context);
    }
    return feInvokeDeclaration(call, function, 1, context);
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
    if (member == 'sublist') return feLowerListSublist(call, type);
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
    feResolveType(call.typeArguments[i]);
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

void feLateFieldState(int field) {
  feOperand(opLoadLocal, 0);
  feOperand(opInt, feLateFieldStates[field]);
  feBuiltinTyped(bObjectGet, 2, tBool);
}

void feLateFieldStore(int field, int value) {
  if (feFieldNodes[field].modifier == 'final') {
    feLateFieldState(field);
    final unwritten = feJump(opJumpFalse);
    feLateFailure(1);
    fePatch(unwritten, ir.length);
  }
  feOperand(opLoadLocal, 0);
  feOperand(opInt, feFieldIndices[field]);
  feOperand(opLoadLocal, value);
  feBuiltinTyped(bObjectSet, 3, feFieldTypes[field]);
  feEmit(opPop);
  feOperand(opLoadLocal, 0);
  feOperand(opInt, feLateFieldStates[field]);
  feInteger(1, tBool);
  feBuiltinTyped(bObjectSet, 3, tBool);
  feEmit(opPop);
}

void feLowerLateField(int function, int field) {
  if (function == feLateFieldSetters[field]) {
    feLateFieldStore(field, 1);
    feOperand(opLoadLocal, 1);
  } else {
    feLateFieldState(field);
    final ready = feJump(opJumpTrue);
    final expression = feFunctionNodes[function].arrow;
    if (expression == null) {
      feLateFailure(0);
    } else {
      feLowerInContext(expression, feFieldTypes[field]);
      final value = feTemp(feFieldTypes[field]);
      feOperand(opStoreLocal, value);
      feLateFieldStore(field, value);
    }
    fePatch(ready, ir.length);
    feOperand(opLoadLocal, 0);
    feOperand(opInt, feFieldIndices[field]);
    feBuiltinTyped(bObjectGet, 2, feFieldTypes[field]);
  }
  feEmit(opReturn);
}

int feFactoryRedirectTarget(int function) {
  final expression = feFunctionNodes[function].factoryRedirect!;
  var targetType = feConstructorType(
    feExpressionSymbol(expression, false),
    expression.typeArguments,
    expression.token,
  );
  var name = '';
  if (targetType < 0 && expression.kind == astMember) {
    final receiver = expression.children[0];
    targetType = feConstructorType(
      feExpressionSymbol(receiver, false),
      receiver.typeArguments,
      receiver.token,
    );
    if (expression.typeArguments.isNotEmpty)
      feAstError(
        expression.token,
        'constructor selector does not accept type arguments',
      );
    name = constructorSelector(feSources, expression.text, expression.token);
  }
  final owner = targetType < 0 ? -1 : resolvedTypeClassOwner(targetType);
  if (owner < 0)
    feAstError(
      expression.token,
      'factory redirect requires a class constructor',
    );
  if (name.startsWith('_') &&
      sourceLibrary(feSources, feTokens[expression.token].source) !=
          sourceLibrary(feSources, feClassSources[owner]))
    feAstError(expression.token, 'private factory redirect target');
  final ordinal = lookupConstructor(feMembers[owner], name);
  if (ordinal < 0)
    feAstError(expression.token, 'unknown factory redirect target');
  final target = feClassConstructors[owner][ordinal];
  if (!feFunctionNodes[target].factory && feClassNodes[owner].isAbstract)
    feAstError(expression.token, 'cannot instantiate an abstract class');
  return target;
}

void feCheckFactoryRedirects() {
  for (var function = 1; function < feFunctionNodes.length; function++) {
    final syntax = feFunctionNodes[function];
    if (syntax.factoryRedirect == null) continue;
    for (final parameter in syntax.parameters)
      if (parameter.defaultValue != null)
        feAstError(
          parameter.token,
          'redirecting factory cannot declare default values',
        );
    final target = feConstructorPlans[function].redirectTarget;
    if (!classSignatureSubtype(
      ClassSignature(
        functions[target].result,
        functions[target].parameterTypes.sublist(feParameterOffset(target)),
        feFunctionNodes[target].parameters,
        const <int>[],
      ),
      ClassSignature(
        functions[function].result,
        functions[function].parameterTypes,
        syntax.parameters,
        const <int>[],
      ),
    ))
      feAstError(
        syntax.factoryRedirect!.token,
        'incompatible factory redirect signature',
      );
  }
}

int feLowerFactoryArguments(AstExpression call, int contract, int target) {
  if (call.typeArguments.isNotEmpty)
    feAstError(call.token, 'nongeneric call does not accept type arguments');
  final sourceParameters = feFunctionNodes[contract].parameters;
  final targetParameters = feFunctionNodes[target].parameters;
  final bindings = bindArguments(feSources, feFunctionNodes[contract], call, 1);
  final offset = feParameterOffset(target);
  final values = List<int>.filled(targetParameters.length, -1);
  for (var a = 1; a < call.children.length; a++) {
    var expression = call.children[a];
    if (expression.kind == astNamedArgument)
      expression = expression.children[0];
    final source = bindings[a - 1];
    final parameter = correspondingParameter(
      targetParameters,
      sourceParameters[source],
      source,
    );
    final sourceType = functions[contract].parameterTypes[source];
    final targetType = functions[target].parameterTypes[offset + parameter];
    feLowerInContext(expression, sourceType);
    // Redirects transfer the payload even when the source contract says void.
    if (sourceType == tVoid && targetType != tVoid)
      feBuiltinTyped(bBoxRef, 1, targetType);
    else
      feConvertValue(sourceType, targetType, expression.token);
    final slot = feTemp(targetType);
    feOperand(opStoreLocal, slot);
    values[parameter] = slot;
  }
  for (var p = 0; p < targetParameters.length; p++) {
    if (values[p] >= 0)
      feOperand(opLoadLocal, values[p]);
    else
      feConstantValue(
        feParamDefaults[target][offset + p],
        functions[target].parameterTypes[offset + p],
        call.token,
      );
  }
  return targetParameters.length;
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
  for (final step in plan.steps) {
    final field = feClassFieldStarts[owner] + step.field;
    final fieldType = feFieldTypes[field];
    feOperand(opLoadLocal, 0);
    feOperand(opInt, feFieldIndices[field]);
    if (step.kind == constructorDeclaration) {
      if (syntax.primary) {
        feBindings = bodyBindings.withReceiver(-1);
        feLowerInContext(feFieldNodes[field].initializer[0], fieldType);
      } else {
        feLowerInitializer(
          feFieldNodes[field],
          feFieldBindings[field],
          fieldType,
        );
      }
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
    if (feFieldNodes[field].lateVariable) {
      feOperand(opLoadLocal, 0);
      feOperand(opInt, feLateFieldStates[field]);
      feInteger(1, tBool);
      feBuiltinTyped(bObjectSet, 3, tBool);
      feEmit(opPop);
    }
  }
  if (plan.superTarget >= 0) {
    feBindings = bodyBindings.withReceiver(-1);
    final target = plan.superTarget;
    final call = plan.superCall!;
    checkArgumentOrder(feSources, call);
    feOperand(opLoadLocal, 0);
    feConvertValue(
      classType(owner),
      functions[target].parameterTypes[0],
      call.token,
    );
    final count = feLowerArguments(call, 1, target);
    feCall(target, count + 1);
    feEmit(opPop);
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
  if (name.startsWith('_') &&
      sourceLibrary(feSources, feTokens[token].source) !=
          sourceLibrary(feSources, feClassSources[owner]))
    feAstError(token, 'private constructor ' + name);
  var ordinal = lookupConstructor(feMembers[owner], name);
  if (ordinal < 0) feAstError(token, 'unknown constructor');
  var constructor = feClassConstructors[owner][ordinal];
  final contract = constructor;
  final result = classType(owner);
  while (feFunctionNodes[constructor].factoryRedirect != null)
    constructor = feConstructorPlans[constructor].redirectTarget;
  owner = feOwners[constructor];
  if (feClassNodes[owner].isAbstract && feConstructors[constructor] == 1)
    feAstError(token, 'cannot instantiate an abstract class');
  final count = contract == constructor
      ? feLowerArguments(call, 1, constructor)
      : feLowerFactoryArguments(call, contract, constructor);
  if (feConstructors[constructor] == 2) {
    feCall(constructor, count);
    feConvertValue(functions[constructor].result, result, token);
    return result;
  }
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
  feConvertValue(functions[constructor].result, result, token);
  return result;
}

int feLowerCall(AstExpression call, int context) {
  checkArgumentOrder(feSources, call);
  var callee = feWithReceiver(call.children[0]);
  if (feIsSuper(callee)) return feLowerSuperCall(call, callee, 'call', context);
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
    var index = feMemberIndex(staticOwner, callee.text, callee.token);
    if (index >= 0 && feMembers[staticOwner].members[index].isStatic) {
      var member = feStaticBinding(staticOwner, callee.text, callee.token);
      return feLowerStaticMemberCall(call, member, context);
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
      return feInvokeDeclaration(call, function, 0, context);
    }
    if (declaration.kind == symbolBuiltin)
      return feLowerBuiltinCall(call, declaration.target);
    var value = feLoadDeclaration(symbol, callee.token);
    if (value == tNever) return feLowerNeverArguments(call);
    return feLowerValueCall(call, value, context);
  }
  if (callee.kind == astMember) return feLowerMemberCall(call, callee, context);
  var value = feLowerExpression(callee);
  if (value == tNever) return feLowerNeverArguments(call);
  return feLowerValueCall(call, value, context);
}

int feLowerMember(AstExpression expression) {
  if (feIsSuper(expression.children[0])) {
    final receiver = expression.children[0];
    final owner = feSuperOwner(receiver);
    feLoadSuper(receiver, owner);
    return feReadCheckedMember(
      feSuperRead(owner, expression.text, expression.token),
      expression.token,
      true,
    );
  }
  final receiverSymbol = feExpressionSymbol(expression.children[0], false);
  if (receiverSymbol >= 0) {
    final declaration = feSymbols.declarations[receiverSymbol];
    if (declaration.source == sourceCore &&
        declaration.kind == symbolType &&
        declaration.target == tDouble) {
      final value = binary64Constant(expression.text);
      if (value != null) {
        feOperand(opDouble, value);
        return tDouble;
      }
    }
  }
  var owner = feStaticOwner(expression);
  if (owner >= 0)
    return feReadStaticMember(
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
  return feReadCheckedMember(feCheckMemberRead(type, member, token), token);
}

CheckedMemberRead feCheckMemberRead(int type, String member, int token) {
  if (type == tNever ||
      (typeIsFunction(type) || type == tFunction) && member == 'call')
    return CheckedMemberRead(type, type, memberReadIdentity, -1);
  if (feClassType(type)) {
    var owner = typeArgument(type);
    feCheckPrivate(owner, member, token);
    var index = feMemberIndex(owner, member, token);
    if (index < 0) feAstError(token, 'unknown member ' + member);
    var binding = feMembers[owner].members[index];
    if (binding.isStatic)
      feAstError(token, 'static member cannot be accessed through an instance');
    return feCheckBoundMember(owner, binding, token);
  }
  if ((type == tInt || type == tDouble || type == tNum || type == tDynamic) &&
      (member == 'isNaN' ||
          member == 'isFinite' ||
          member == 'isInfinite' ||
          member == 'isNegative')) {
    final property = switch (member) {
      'isNaN' => 0,
      'isFinite' => 1,
      'isInfinite' => 2,
      _ => 3,
    };
    return CheckedMemberRead(
      type,
      type == tDynamic ? tDynamic : tBool,
      memberReadNumberProperty,
      property,
    );
  }
  if (member == 'length' || member == 'isEmpty' || member == 'isNotEmpty') {
    if (type != tString && !typeIsList(type))
      feAstError(token, 'unsupported property ' + member);
    var kind = member == 'length'
        ? memberReadLength
        : member == 'isEmpty'
        ? memberReadIsEmpty
        : memberReadIsNotEmpty;
    return CheckedMemberRead(type, member == 'length' ? tInt : tBool, kind, -1);
  }
  if (typeIsList(type) && (member == 'first' || member == 'last'))
    return CheckedMemberRead(
      type,
      typeArgument(type),
      member == 'first' ? memberReadFirst : memberReadLast,
      -1,
    );
  feAstError(token, 'unsupported property ' + member);
}

CheckedMemberRead feCheckBoundMember(
  int owner,
  MemberBinding member,
  int token, [
  bool direct = false,
]) {
  var receiver = classType(owner);
  if (!direct &&
      feNeedsDispatch(owner) &&
      member.method < 0 &&
      hasClassMember(member, classGetter)) {
    final target = feDispatchMember(owner, member, classGetter, const <int>[]);
    return CheckedMemberRead(
      receiver,
      functions[target].result,
      memberReadGetter,
      target,
    );
  }
  if (member.method >= 0) {
    var function = member.method;
    return CheckedMemberRead(
      receiver,
      feCallableType(function, token),
      memberReadMethod,
      function,
    );
  }
  if (member.getter >= 0) {
    var getter = member.getter;
    return CheckedMemberRead(
      receiver,
      functions[getter].result,
      memberReadGetter,
      getter,
    );
  }
  if (member.field >= 0) {
    var field = member.field;
    return CheckedMemberRead(
      receiver,
      feFieldTypes[field],
      feFieldNodes[field].lateVariable ? memberReadGetter : memberReadField,
      feFieldNodes[field].lateVariable
          ? feLateFieldGetters[field]
          : feFieldIndices[field],
    );
  }
  feAstError(token, 'member has no getter: ' + member.name);
}

int feReadCheckedMember(
  CheckedMemberRead member,
  int token, [
  bool direct = false,
]) {
  var kind = member.kind;
  if (kind == memberReadMethod || kind == memberReadGetter)
    feConvertValue(
      member.receiver,
      functions[member.target].parameterTypes[0],
      token,
    );
  if (kind == memberReadNumberProperty) {
    feConvertValue(member.receiver, tDynamic, token);
    feOperand(opInt, member.target);
    feBuiltin(bNumberProperty, 2);
    feConvertValue(tBool, member.type, token);
  }
  if (kind == memberReadMethod)
    return feCreateBoundMethod(member.target, token, direct);
  if (kind == memberReadGetter) {
    feCall(member.target, 1);
  } else if (kind == memberReadField) {
    feOperand(opInt, member.target);
    feBuiltinTyped(bObjectGet, 2, member.type);
  } else if (kind == memberReadLength ||
      kind == memberReadIsEmpty ||
      kind == memberReadIsNotEmpty) {
    feBuiltin(member.receiver == tString ? bStringLength : bListLength, 1);
    if (kind != memberReadLength) {
      feOperand(opInt, 0);
      feEmit(kind == memberReadIsEmpty ? opEq : opNe);
    }
  } else if (kind == memberReadFirst || kind == memberReadLast) {
    if (kind == memberReadFirst)
      feOperand(opInt, 0);
    else {
      feDuplicate(member.receiver);
      feBuiltin(bListLength, 1);
      feOperand(opInt, 1);
      feEmit(opSub);
    }
    feBuiltinTyped(bListGet, 2, member.type);
  }
  return member.type;
}

int feReadBoundMember(int owner, MemberBinding member, int token) {
  if (member.isStatic) return feReadStaticMember(member, token);
  return feReadCheckedMember(feCheckBoundMember(owner, member, token), token);
}

FeLvalue feLowerLvalue(AstExpression expression, bool reading) {
  expression = feWithReceiver(expression);
  if (expression.kind == astMember && feIsSuper(expression.children[0]))
    return feLowerSuperLvalue(expression, reading);
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
      setter = member.setter;
      type = functions[setter].parameterTypes[0];
    } else if (member.staticField >= 0) {
      global = member.staticField;
      if (!feGlobalNodes[global].hasSetter)
        feAstError(expression.token, 'cannot assign a final field');
      type = feGlobalType(global);
    } else {
      feAstError(expression.token, 'member has no setter: ' + member.name);
    }
    if (reading) feStaticReadType(member, expression.token);
    var target = FeLvalue(type, setter >= 0 ? 5 : 0, -1, -1, -1, global);
    target.owner = staticOwner;
    target.member = feMemberIndex(staticOwner, member.name, expression.token);
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
    var entry = feMemberIndex(owner, expression.text, expression.token);
    if (entry < 0)
      feAstError(expression.token, 'unknown member ' + expression.text);
    var member = feMembers[owner].members[entry];
    if (member.isStatic)
      feAstError(
        expression.token,
        'static member cannot be accessed through an instance',
      );
    if (feNeedsDispatch(owner) && hasClassMember(member, classSetter)) {
      final setter = feDispatchMember(owner, member, classSetter, const <int>[
        0,
      ]);
      final receiver = feTemp(receiverType);
      feOperand(opStoreLocal, receiver);
      return FeLvalue(
          functions[setter].parameterTypes[1],
          4,
          receiver,
          -1,
          -1,
          -1,
        )
        ..owner = owner
        ..member = entry
        ..setter = setter;
    }
    if (member.setter >= 0) {
      var setter = member.setter;
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
    if (member.fieldSetter < 0)
      feAstError(expression.token, 'member has no setter: ' + member.name);
    var field = member.fieldSetter;
    if (feFieldNodes[field].lateVariable) {
      final receiver = feTemp(receiverType);
      feOperand(opStoreLocal, receiver);
      return FeLvalue(feFieldTypes[field], 4, receiver, -1, -1, -1)
        ..owner = owner
        ..member = entry
        ..setter = feLateFieldSetters[field];
    }
    feOperand(opInt, feFieldIndices[field]);
    final index = feTemp(tInt);
    feOperand(opStoreLocal, index);
    final receiver = feTemp(receiverType);
    feOperand(opStoreLocal, receiver);
    return FeLvalue(feFieldTypes[field], 2, receiver, index, -1, -1)
      ..owner = owner
      ..member = entry;
  }
  var index = feTemp(tInt);
  feOperand(opStoreLocal, index);
  var receiver = feTemp(receiverType);
  feOperand(opStoreLocal, receiver);
  return FeLvalue(type, 1, receiver, index, -1, -1);
}

FeLvalue feLowerSuperLvalue(AstExpression expression, bool reading) {
  final source = expression.children[0];
  final owner = feSuperOwner(source);
  final member = feSuperImplementation(
    owner,
    expression.text,
    classSetter,
    expression.token,
  );
  if (member == null)
    feAstError(
      expression.token,
      'super member has no concrete setter: ' + expression.text,
    );
  final type = feLoadSuper(source, owner);
  final receiver = feTemp(type);
  feOperand(opStoreLocal, receiver);
  final function = member.setter;
  var field = -1;
  var index = -1;
  if (function < 0) {
    field = member.fieldSetter;
    index = feTemp(tInt);
    feOperand(opInt, feFieldIndices[field]);
    feOperand(opStoreLocal, index);
  }
  final setter = function >= 0 ? function : feLateFieldSetters[field];
  final target = FeLvalue(
    function >= 0 ? functions[function].parameterTypes[1] : feFieldTypes[field],
    setter >= 0 ? 4 : 2,
    receiver,
    index,
    -1,
    -1,
  )..setter = setter;
  if (reading)
    target.directRead = feSuperRead(owner, expression.text, expression.token);
  return target;
}

int feReadLvalue(FeLvalue target, int token) {
  if (target.directRead case final read?) {
    feOperand(opLoadLocal, target.receiver);
    return feReadCheckedMember(read, token, true);
  }
  if (target.container == 3) {
    feOperand(opLoadLocal, target.receiver);
    return tNever;
  }
  if ((target.container == 0 || target.container == 5) && target.owner >= 0)
    return feReadStaticMember(
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
  if (target.owner >= 0) {
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
  if (target.binding >= 0) {
    final variable = feBindings.variables[target.binding];
    final assigned = feFlow.assignments[target.binding];
    if (variable.finalVariable &&
        (variable.lateVariable
            ? assigned == flowAssigned
            : variable.outer >= 0 || assigned != flowUnassigned))
      feAstError(token, 'final variable might already be assigned');
    if (variable.lateVariable) {
      feStoreLateLocal(target.binding, token);
      return;
    }
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
    final setter = target.setter >= 0
        ? target.setter
        : feMembers[target.owner].members[target.member].setter;
    feConvertValue(
      feSlotTypes[target.receiver],
      functions[setter].parameterTypes[0],
      token,
    );
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
    var right = feLowerHint(
      expression.children[1],
      typingBinaryContext(
        op.substring(0, op.length - 1),
        readType,
        target.type,
      ),
    );
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
  feFlow = .copy(afterLeft);
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
    if (type == tDynamic || typeIsParameter(result)) checked = tObject;
    feOperand(opTypeCast, checked);
    if (checked != result) {
      if (typeIsParameter(result))
        feBuiltinTyped(bBoxRef, 1, result);
      else
        feConvertValue(checked, result, expression.token);
    }
  }
  if (source.kind == astName &&
      source.binding >= 0 &&
      fePromotable(source.binding))
    feFlow.types[source.binding] = result;
  if (result == tNever) flowUnreachable(feFlow);
  return result;
}

int feLowerExpression(AstExpression expression) {
  if (expression.kind == astPatternAssignment)
    return feLowerPatternAssignment(expression);
  var type = feLowerValue(expression);
  if (type == tNever) flowUnreachable(feFlow);
  return type;
}

int feLowerValue(AstExpression expression) {
  if (expression.kind == astStaticShorthand) return feLowerHint(expression, -1);
  if (expression.kind == astThrow) {
    final value = expression.children[0];
    final type = feLowerAssignedValue(value, tObject);
    if (type != tDynamic && typeCanBeNull(type))
      feAstError(value.token, 'throw requires a non-nullable value');
    feConvertValue(type, tObject, value.token);
    feCall(feFindFunction('rtThrow'), 1);
    return tNever;
  }
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
  if (kind == astDouble) {
    feOperand(opDouble, decodeDoubleLiteral(feSources, expression));
    return tDouble;
  }
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
    if (feIsSuper(expression))
      feAstError(expression.token, 'super requires a member selector');
    var owner = feStaticOwner(expression);
    if (owner >= 0)
      return feReadStaticMember(
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
    var target = feResolveType(expression.typeArguments[0]);
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
    var bound = typeBound(type);
    if (bound != type) type = feConvertValue(type, bound, expression.token);
    var result = typingUnary(op, type);
    if (result < 0) feAstError(expression.token, 'invalid unary operand type');
    if (result == tNever) return tNever;
    if (type == tDouble) {
      feEmit(opDoubleNeg);
      return tDouble;
    }
    if ((type == tNum || type == tDynamic) && op == '-') {
      feBuiltinTyped(bValueNeg, 1, result);
      return result;
    }
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
    var right = feLowerHint(
      resolveEqualityShorthand(feSymbols, op, expression.children[1], left),
      typingBinaryContext(op, left, -1),
    );
    return feCombine(op, left, right, expression.token);
  }
  if (kind == astConditional) return feLowerConditional(expression, -1);
  feAstError(expression.token, 'unsupported expression');
}

FlowState feNullBranch(AstExpression source, int type) {
  feFlow = flowSplit(feFlow);
  var skipped = FlowState.copy(feFlow);
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
  feFlow = .copy(afterLeft);
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

// Late state is distinct from the payload, so every Dart value, including null,
// remains usable. Only captured locals require a shared heap cell.
void feLateFailure(int write) {
  final normal = feFlow;
  feFlow = .copy(normal);
  feOperand(opInt, write);
  feBuiltin(bLateError, 1);
  feEmit(opPop);
  feFlow = normal;
}

int feLateInitializerType(int binding) {
  final syntax = bindingDeclaration(feBindings, binding).lateInitializer!;
  return functionValueType(feLocalStart + syntax.local);
}

void feLateLoadPart(int binding, int part) {
  if (feCellBinding(binding)) {
    feOperand(opLoadLocal, feBindingSlots[binding]);
    feOperand(opInt, part);
    feBuiltinTyped(
      bObjectGet,
      2,
      part == 1 ? tBool : feLateInitializerType(binding),
    );
  } else {
    final local = feLateLocals[binding]!;
    feOperand(opLoadLocal, part == 1 ? local.state : local.initializer);
  }
}

void feLateStorePart(int binding, int part, int type) {
  if (feCellBinding(binding)) {
    final value = feTemp(type);
    feOperand(opStoreLocal, value);
    feOperand(opLoadLocal, feBindingSlots[binding]);
    feOperand(opInt, part);
    feOperand(opLoadLocal, value);
    feBuiltinTyped(bObjectSet, 3, type);
    feEmit(opPop);
  } else {
    final local = feLateLocals[binding]!;
    feOperand(
      opStoreLocal,
      part == 0
          ? feBindingSlots[binding]
          : part == 1
          ? local.state
          : local.initializer,
    );
  }
}

void feStoreLateLocal(int binding, int token) {
  final type = feBindingTypes[binding];
  final value = feTemp(type);
  feOperand(opStoreLocal, value);
  if (feBindings.variables[binding].finalVariable) {
    feLateLoadPart(binding, 1);
    final unwritten = feJump(opJumpFalse);
    feLateFailure(1);
    fePatch(unwritten, ir.length);
  }
  feOperand(opLoadLocal, value);
  feLateStorePart(binding, 0, type);
  feInteger(1, tBool);
  feLateStorePart(binding, 1, tBool);
  if (bindingDeclaration(feBindings, binding).lateInitializer != null) {
    final initializerType = feLateInitializerType(binding);
    feInteger(0, initializerType);
    feLateStorePart(binding, 2, initializerType);
  }
  feOperand(opLoadLocal, value);
}

void feInitializeLateLocal(int binding, int token) {
  final declaration = bindingDeclaration(feBindings, binding);
  feLateLoadPart(binding, 1);
  final ready = feJump(opJumpTrue);
  if (declaration.lateInitializer == null) {
    feLateFailure(0);
  } else {
    final function = feLocalStart + declaration.lateInitializer!.local;
    final captured = functions[function].closureLayout != null;
    if (captured) feLateLoadPart(binding, 2);
    final normal = feFlow;
    feFlow = .copy(normal);
    feCall(function, captured ? 1 : 0);
    feFlow = normal;
    feConvertValue(functions[function].result, feBindingTypes[binding], token);
    feStoreLateLocal(binding, token);
    feEmit(opPop);
  }
  fePatch(ready, ir.length);
}

void feLowerLateVariable(AstVariable variable, int type) {
  final binding = variable.binding;
  final initializer = variable.lateInitializer;
  if (initializer != null) {
    feLocalContexts[initializer.local] = type;
    fePrepareLocalFunction(initializer);
    if (type < 0) {
      type = functions[feLocalStart + initializer.local].result;
      if (type == tNull) type = tDynamic;
    }
  }
  final captured = feCellBinding(binding);
  // Uninitialized storage is not an instance of the declared Never type.
  final storage = type == tNever ? tNull : type;
  final slot = feTemp(captured ? tObject : storage);
  if (captured) {
    feOperand(opLateCellDescriptor, type);
    feBuiltinTyped(bObjectNew, 1, tObject);
  } else {
    feInteger(0, storage);
    feLateLocals[binding] = FeLateLocal(
      feTemp(tBool),
      initializer == null
          ? -1
          : feTemp(functionValueType(feLocalStart + initializer.local)),
    );
  }
  feOperand(opStoreLocal, slot);
  feBindLocal(binding, type, slot);
  feInteger(0, tBool);
  feLateStorePart(binding, 1, tBool);
  if (initializer != null) {
    final actual = feCreateClosure(
      feLocalStart + initializer.local,
      variable.token,
    );
    feLateStorePart(binding, 2, actual);
  }
  flowDeclare(feFlow, binding, type, initializer != null);
  if (initializer != null && variable.modifier != 'final') {
    flowWrite(
      feFlow,
      binding,
      type,
      functions[feLocalStart + initializer.local].result,
    );
    if (!fePromotable(binding)) feFlow.types[binding] = type;
  }
}

void feLowerVariable(AstVariable variable) {
  feAt = variable.token;
  feCheckMetadata(variable.metadata, feLexicalOwner(feFunction));
  var type = -1;
  if (variable.type.name != '') type = feResolveType(variable.type);
  if (type < 0 && variable.initializer.isEmpty) type = tDynamic;
  if (variable.lateVariable) {
    feLowerLateVariable(variable, type);
    return;
  }
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
  else {
    if (type == tNever) value = tNull;
    feInteger(0, value);
  }
  if (type < 0) {
    if (value == tNull) value = feConvertValue(value, tDynamic, variable.token);
    type = value;
  }
  final storage = type == tNever && variable.initializer.isEmpty ? tNull : type;
  feConvertValue(value, storage, variable.token);
  var cell = feCellBinding(variable.binding);
  if (cell) feAllocateCell(storage);
  var slot = feTemp(cell ? tObject : storage);
  feBindLocal(variable.binding, type, slot);
  flowDeclare(
    feFlow,
    variable.binding,
    type,
    typeIsSubtype(tNull, type) &&
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
  if (statement.kind == astForInStatement &&
      statement.variables.isEmpty &&
      statement.patternDeclaration == null)
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
  final declaration = feLocalFunctions[local];
  final function = feLocalStart + local;
  final previous = FeFunctionState();
  final context = feLocalContexts[local];
  var result = tNever;
  try {
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
    final arrow = declaration.syntax.arrow;
    if (arrow != null) {
      result = feLowerAssignedValue(arrow, context);
    } else {
      final body = declaration.syntax.body;
      if (body != null) feLowerStatement(body);
      if (feFlow.reachable) result = tNull;
      for (final returned in feReturnTypes!)
        result = joinTypes(result, returned);
    }
  } finally {
    previous.restore();
  }
  if (context >= 0 && (context == tVoid || !typeIsSubtype(result, context)))
    result = context;
  functions[function].result = result;
  functions[function].callableType = -1;
  feLocalInferred[local] = true;
}

void fePrepareLocalFunction(AstFunction syntax) {
  final function = feLocalStart + syntax.local;
  feResolveFunctionDefaults(function);
  final bindings = feLocalFunctions[syntax.local].body!;
  final closure = feLocalClosures[syntax.local];
  final layout = functions[function].closureLayout;
  if (!closure.prepared) {
    closure.prepared = true;
    if (layout != null) {
      for (var binding in bindings.captures) {
        final variable = bindings.variables[binding];
        if (variable.function == syntax.local) continue;
        final original = variable.outer;
        final type = feBindingTypes[original];
        if (type < 0)
          feAstError(syntax.token, 'captured variable has no declared type');
        final declaration = bindingDeclaration(feBindings, original);
        final promoted = declaration.written ? type : feFlow.types[original];
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
    final variable = bindings.variables[i];
    if (variable.outer >= 0 && variable.constant) {
      final original = variable.outer;
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
  final type = feCallableType(function, token);
  var signature = -1;
  if (typeContainsParameters(type)) {
    feRuntimeType(type);
    signature = feTemp(tObject);
    feOperand(opStoreLocal, signature);
  }
  feOperand(opClosureDescriptor, function);
  feBuiltinTyped(bObjectNew, 1, type);
  final closure = feTemp(type);
  feOperand(opStoreLocal, closure);
  var field = 0;
  while (field < 2) {
    feOperand(opLoadLocal, closure);
    feOperand(opInt, field);
    var fieldType = tPointer;
    if (field == 0 && signature >= 0) {
      feOperand(opLoadLocal, signature);
      fieldType = tObject;
    } else {
      feFunctionReference(function, token);
      feBuiltin(field == 0 ? bFunctionType : bFunctionEntry, 1);
    }
    feBuiltinTyped(bObjectSet, 3, fieldType);
    feEmit(opPop);
    field++;
  }
  return closure;
}

int feCreateBoundMethod(int function, int token, [bool direct = false]) {
  if (!direct && feNeedsDispatch(feOwners[function])) {
    final owner = feOwners[function];
    final syntax = feFunctionNodes[function];
    final member =
        feMembers[owner].members[lookupMember(
          feMembers[owner],
          syntax.name,
          sourceLibrary(feSources, feTokens[syntax.token].source),
        )];
    final target = feDispatchMember(owner, member, classTearoff, const <int>[]);
    feCall(target, 1);
    return functions[target].result;
  }
  final receiverType = functions[function].parameterTypes[0];
  final receiver = feTemp(receiverType);
  feOperand(opStoreLocal, receiver);
  final closure = feAllocateClosure(function, token);
  feOperand(opLoadLocal, closure);
  feOperand(opInt, 2);
  feOperand(opLoadLocal, receiver);
  feBuiltinTyped(bObjectSet, 3, receiverType);
  feEmit(opPop);
  feOperand(opLoadLocal, closure);
  return feSlotTypes[closure];
}

int feCreateClosure(int function, int token) {
  final layout = functions[function].closureLayout;
  if (layout == null) return feFunctionReference(function, token);
  final closure = feAllocateClosure(function, token);
  final local = function - feLocalStart;
  final bindings = feLocalFunctions[local].body!;
  var captureIndex = layout.valueCaptureOffset;
  if (captureIndex != 0) {
    feOperand(opLoadLocal, closure);
    feOperand(opInt, 2);
    feLoadCurrentTypeEnvironment();
    feBuiltinTyped(bObjectSet, 3, listType(tObject));
    feEmit(opPop);
  }
  for (var capture in feLocalClosures[local].captures) {
    final original = bindings.variables[capture.binding].outer;
    feOperand(opLoadLocal, closure);
    feOperand(opInt, 2 + captureIndex);
    if (feCellBinding(original))
      feOperand(opLoadLocal, feLocalSlot(original, token));
    else {
      final value = feReadLocal(original, token);
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
  if (kind == astTryStatement) {
    feLowerTry(statement);
    return;
  }
  if (kind == astRethrowStatement) {
    feRethrow(feCatches.last);
    return;
  }
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
  if (kind == astPatternDeclarationStatement) {
    var declaration = statement.patternDeclaration!;
    feCheckMetadata(declaration.metadata, feLexicalOwner(feFunction));
    var context = patternContextType(
      feConstants,
      declaration.pattern,
      feBindingTypes,
    );
    var type = feLowerAssignedValue(statement.expressions[0], context);
    feLowerDestructure(declaration.pattern, type);
    feEmit(opPop);
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
    if (feConstructors[feFunction] == 1 && statement.expressions.isNotEmpty)
      feAstError(
        statement.token,
        'generative constructor cannot return a value',
      );
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
      feCompleteReturn(type);
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
    feCompleteReturn(functions[feFunction].result);
    return;
  }
  if (kind == astIfStatement) {
    feFlow = flowSplit(feFlow);
    var otherwise = <int>[];
    var falseFlow = feIfConditionJumps(statement.condition[0], otherwise);
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
    feCompleteJump(false, feLoopBreaks.length - 1, null);
    return;
  }
  if (kind == astContinueStatement) {
    if (statement.expressions.isNotEmpty) {
      feLowerLabeledJump(statement, true);
      return;
    }
    if (feLoopContinues.isEmpty) feError('continue outside loop');
    feCompleteJump(true, feLoopContinues.length - 1, null);
    return;
  }
  feAstError(statement.token, 'unsupported statement');
}

void feRethrow(FeCatch caught) {
  feOperand(opLoadLocal, caught.value);
  feOperand(opLoadLocal, caught.trace);
  feCall(feFindFunction('rtRethrow'), 2);
}

void feLowerTry(AstStatement statement) {
  if (statement.children.length == 2)
    feLowerTryFinally(statement);
  else
    feLowerTryCatch(statement);
}

void feLowerTryCatch(AstStatement statement) {
  if (statement.catches.isEmpty) {
    feLowerStatement(statement.children[0]);
    return;
  }
  feFlow = flowSplit(feFlow);
  final caughtFlow = FlowState.copy(feFlow);
  final written = <int>[];
  collectWrittenStatement(
    statement.children[0],
    List<bool>.filled(feBindings.variables.length, false),
    written,
  );
  flowDemote(caughtFlow, written, feBindingTypes);
  final handler = feJump(opBeginTry);
  feLowerStatement(statement.children[0]);
  feEmit(opEndTry);
  final done = <int>[feJump(opJump)];
  var completed = feFlow;
  fePatch(handler, ir.length);
  feFlow = .copy(caughtFlow);
  feCall(feFindFunction('rtCaughtException'), 0);
  final value = feTemp(tObject);
  feOperand(opStoreLocal, value);
  final traceFunction = feFindFunction('rtCaughtTrace');
  final traceType = functions[traceFunction].result;
  feCall(traceFunction, 0);
  final trace = feTemp(traceType);
  feOperand(opStoreLocal, trace);
  feCall(feFindFunction('rtClearException'), 0);
  feEmit(opPop);
  final caught = FeCatch(value, trace);
  for (var clause in statement.catches) {
    feFlow = .copy(caughtFlow);
    final type = clause.type == null ? tObject : feResolveType(clause.type!);
    feOperand(opLoadLocal, value);
    feConvertValue(tObject, tDynamic, statement.token);
    feOperand(opTypeTest, type);
    final next = feJump(opJumpFalse);
    for (var i = 0; i < clause.parameters.length; i++) {
      final parameter = clause.parameters[i];
      final parameterType = i == 0 ? type : traceType;
      feOperand(opLoadLocal, i == 0 ? value : trace);
      if (i == 0) feNarrowValue(tObject, type);
      final slot = feTemp(parameterType);
      feOperand(opStoreLocal, slot);
      feBindLocal(parameter.binding, parameterType, slot);
    }
    feCatches.add(caught);
    feLowerStatement(clause.body);
    feCatches.removeLast();
    completed = feJoinFlow(completed, feFlow);
    done.add(feJump(opJump));
    fePatch(next, ir.length);
  }
  feRethrow(caught);
  fePatchJumps(done, ir.length);
  feFlow = flowUnsplit(completed);
}

void feRouteCompletion(
  FeFinally cleanup,
  int kind,
  int target,
  ControlLabel? label,
) {
  final flow = flowUnsplitTo(feFlow, cleanup.flowDepth);
  var index = 0;
  while (index < cleanup.completions.length) {
    final completion = cleanup.completions[index];
    if (completion.kind == kind &&
        completion.target == target &&
        completion.label == label) {
      completion.flow = feJoinFlow(completion.flow, flow);
      break;
    }
    index++;
  }
  if (index == cleanup.completions.length)
    cleanup.completions.add(FeCompletion(kind, target, label, flow));
  feOperand(opInt, index);
  feOperand(opStoreLocal, cleanup.tag);
  cleanup.entries.add(feJump(opJump));
  flowUnreachable(feFlow);
}

void feCompleteReturn(int type) {
  if (feFinalizers.isEmpty || type == tNever) {
    feEmit(opReturn);
  } else {
    final cleanup = feFinalizers.last;
    if (type == tVoid) {
      feEmit(opPop);
      feInteger(0, tNull);
      type = tNull;
    }
    feConvertValue(type, feSlotTypes[cleanup.returned], feAt);
    feOperand(opStoreLocal, cleanup.returned);
    feRouteCompletion(cleanup, completionReturn, -1, null);
  }
  flowUnreachable(feFlow);
}

void feCompleteJump(bool repeat, int target, ControlLabel? label) {
  for (var i = feFinalizers.length - 1; i >= 0; i--) {
    final cleanup = feFinalizers[i];
    final crosses = label == null
        ? target < (repeat ? cleanup.continueDepth : cleanup.breakDepth)
        : label.finallyDepth <= i;
    if (crosses) {
      feRouteCompletion(
        cleanup,
        repeat ? completionContinue : completionBreak,
        target,
        label,
      );
      return;
    }
  }
  final jump = feJump(opJump);
  final flow = FlowState.copy(feFlow);
  if (label != null) {
    if (repeat) {
      label.continues.add(jump);
      label.continueFlows.add(flow);
    } else {
      label.breaks.add(jump);
      label.breakFlows.add(flow);
    }
  } else if (repeat) {
    feContinues.add(jump);
    feContinueFlows.add(flow);
  } else {
    feBreaks.add(jump);
    feBreakFlows.add(flow);
  }
  flowUnreachable(feFlow);
}

int feInitializedTemp(int type) {
  final slot = feTemp(type);
  feInteger(0, type);
  feOperand(opStoreLocal, slot);
  return slot;
}

void feLowerTryFinally(AstStatement statement) {
  feFlow = flowSplit(feFlow);
  final beforeTry = FlowState.copy(feFlow);
  final written = <int>[];
  final seen = List<bool>.filled(feBindings.variables.length, false);
  collectWrittenStatement(statement.children[0], seen, written);
  for (var clause in statement.catches)
    collectWrittenStatement(clause.body, seen, written);

  final result = feReturnTypes == null
      ? functions[feFunction].result
      : tDynamic;
  final stored = result == tVoid || result == tNever
      ? tNull
      : result == tInt ||
            result == tBool ||
            result == tDouble ||
            result == tPointer
      ? result
      : nullableType(result);
  final traceFunction = feFindFunction('rtCaughtTrace');
  final traceType = functions[traceFunction].result;
  final cleanup = FeFinally(
    feTemp(tInt),
    feInitializedTemp(stored),
    FeCatch(
      feInitializedTemp(nullableType(tObject)),
      feInitializedTemp(nullableType(traceType)),
    ),
  );
  feFinalizers.add(cleanup);
  final handler = feJump(opBeginTry);
  feLowerTryCatch(statement);
  feEmit(opEndTry);
  final afterTry = FlowState.copy(feFlow);
  feRouteCompletion(cleanup, completionNormal, -1, null);
  fePatch(handler, ir.length);
  feCall(feFindFunction('rtCaughtException'), 0);
  feConvertValue(tObject, feSlotTypes[cleanup.caught.value], statement.token);
  feOperand(opStoreLocal, cleanup.caught.value);
  feCall(traceFunction, 0);
  feConvertValue(traceType, feSlotTypes[cleanup.caught.trace], statement.token);
  feOperand(opStoreLocal, cleanup.caught.trace);
  feCall(feFindFunction('rtClearException'), 0);
  feEmit(opPop);
  feRouteCompletion(cleanup, completionThrow, -1, null);

  feFinalizers.removeLast();
  fePatchJumps(cleanup.entries, ir.length);
  flowDemote(beforeTry, written, feBindingTypes);
  final beforeFinally = feJoinFlow(afterTry, beforeTry);
  feFlow = .copy(beforeFinally);
  feLowerStatement(statement.children[1]);
  final afterFinally = feFlow;
  final done = <int>[];
  for (var i = 0; i < cleanup.completions.length; i++) {
    final completion = cleanup.completions[i];
    feOperand(opLoadLocal, cleanup.tag);
    feOperand(opInt, i);
    feEmit(opEq);
    final next = feJump(opJumpFalse);
    // Jump targets use the source jump's flow facts, as in Dart flow analysis.
    // Cleanup dispatch must not add definite assignments to those facts.
    feFlow = .copy(completion.flow);
    if (completion.kind == completionNormal) {
      done.add(feJump(opJump));
    } else if (completion.kind == completionReturn) {
      if (result == tVoid)
        feInteger(0, tVoid);
      else {
        feOperand(opLoadLocal, cleanup.returned);
        feNarrowValue(stored, result);
      }
      feCompleteReturn(result);
    } else if (completion.kind == completionThrow) {
      feOperand(opLoadLocal, cleanup.caught.value);
      feNarrowValue(feSlotTypes[cleanup.caught.value], tObject);
      feOperand(opLoadLocal, cleanup.caught.trace);
      feNarrowValue(feSlotTypes[cleanup.caught.trace], traceType);
      feCall(feFindFunction('rtRethrow'), 2);
    } else {
      feCompleteJump(
        completion.kind == completionContinue,
        completion.target,
        completion.label,
      );
    }
    fePatch(next, ir.length);
  }
  feEmit(opUnreachable);
  fePatchJumps(done, ir.length);
  feFlow = flowUnsplit(
    flowAttachFinally(afterTry, beforeFinally, afterFinally),
  );
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
  final previousLate = feLateLocals;
  var previousFlow = feFlow;
  var previousConstants = feConstants.locals;
  var previousConstantTypes = feConstants.localTypes;
  feBindings = bindings;
  feBindingTypes = List<int>.filled(bindings.variables.length, -1);
  feBindingSlots = List<int>.filled(bindings.variables.length, -1);
  feLateLocals = List<FeLateLocal?>.filled(bindings.variables.length, null);
  feConstants.locals = <ConstantValue>[];
  feConstants.localTypes = <int>[];
  feFlow = .create(
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
  feLateLocals = previousLate;
  feFlow = previousFlow;
  feConstants.locals = previousConstants;
  feConstants.localTypes = previousConstantTypes;
  return type;
}

void feInferGlobal(int global) {
  final initializer = feGlobalInitializers[global];
  if (initializer.code.isNotEmpty) return;
  if (initializer.result == -1)
    feError('cannot infer global type ' + globalNames[global]);
  initializer.result = -1;
  final previous = FeFunctionState();
  try {
    feConstants.lexicalClass = feGlobalOwners[global];
    ir = <int>[];
    irTypes = <int>[];
    feSlotTypes = <int>[];
    feNextLocal = 0;
    feInitializingGlobal = global;
    final syntax = feGlobalNodes[global];
    var type = feLowerInitializer(
      syntax,
      initializer.bindings,
      globalTypes[global],
    );
    if (globalTypes[global] < 0) {
      if (type == tNull) type = feConvertValue(type, tDynamic, syntax.token);
      globalTypes[global] = type;
    }
    initializer.result = globalTypes[global];
    initializer.code = ir;
    initializer.types = irTypes;
    initializer.locals = feSlotTypes;
    final getter = functions[initializer.getter];
    getter.result = initializer.result;
    final setter = functions[initializer.setter];
    setter.result = initializer.result;
    setter.parameterTypes[0] = initializer.result;
    setter.localTypes[0] = initializer.result;
  } finally {
    previous.restore();
  }
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
      final syntax = feGlobalNodes[i];
      if (syntax.lateVariable && syntax.initializer.isEmpty) feLateFailure(0);
      feAppendInitializer(initializer);
      if (syntax.modifier == 'final') {
        final value = feTemp(globalTypes[i]);
        feOperand(opStoreLocal, value);
        feOperand(opLoadGlobal, initializer.state);
        feOperand(opInt, 2);
        feEmit(opEq);
        final unwritten = feJump(opJumpFalse);
        feLateFailure(1);
        fePatch(unwritten, ir.length);
        feOperand(opLoadLocal, value);
      }
      feOperand(opStoreGlobal, i);
      feOperand(opInt, 2);
      feOperand(opStoreGlobal, initializer.state);
      feOperand(opLoadGlobal, i);
      feEmit(opReturn);
      getter.locals = feNextLocal;
      getter.localTypes = feSlotTypes;
      getter.end = ir.length;
      var setter = functions[initializer.setter];
      setter.start = ir.length;
      feSlotTypes = <int>[globalTypes[i]];
      feNextLocal = 1;
      if (syntax.lateVariable && syntax.modifier == 'final') {
        feOperand(opLoadGlobal, initializer.state);
        feOperand(opInt, 2);
        feEmit(opEq);
        final unwritten = feJump(opJumpFalse);
        feLateFailure(1);
        fePatch(unwritten, ir.length);
      }
      feOperand(opLoadLocal, 0);
      feOperand(opStoreGlobal, i);
      feOperand(opInt, 2);
      feOperand(opStoreGlobal, initializer.state);
      feOperand(opLoadLocal, 0);
      feEmit(opReturn);
      setter.locals = 1;
      setter.localTypes = feSlotTypes;
      setter.end = ir.length;
    }
    i++;
  }
}

void feBeginFunction(int f, FunctionBindings bindings) {
  feFunction = f;
  feCatches = <FeCatch>[];
  feFinalizers = <FeFinally>[];
  feConstants.typeScope = functions[f].typeScope;
  feImplicitReceiverSlot = -1;
  feConstants.lexicalClass = -1;
  final owner = feLexicalOwner(f);
  feConstants.lexicalClass = owner;
  final functionSyntax = feFunctionNodes[f];
  feAt = functionSyntax.token;
  feBindings = bindings;
  feConstants.locals.clear();
  if (f >= feLocalStart) {
    final values = feLocalConstants[f - feLocalStart];
    if (values != null) {
      var i = 0;
      while (i < values.length) {
        feConstants.locals.add(values[i]);
        i++;
      }
    }
  }
  feFlow = .create(
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
  feLateLocals = List<FeLateLocal?>.filled(feBindings.variables.length, null);
  var binding = 0;
  while (binding < feBindings.variables.length) {
    feBindingTypes.add(-1);
    feBindingSlots.add(-1);
    binding++;
  }
  binding = 0;
  while (binding < feBindings.variables.length) {
    final variable = feBindings.variables[binding];
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
    if (functions[f].typeParameters.isNotEmpty &&
        p == feTypeEnvironmentSlot(f)) {
      p++;
      continue;
    }
    final type = functions[f].parameterTypes[p];
    var slot = p;
    var binding = feBindings.receiver;
    final parameter = p - feParameterOffset(f);
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
    final local = f - feLocalStart;
    var captureIndex = context.valueCaptureOffset;
    for (var capture in feLocalClosures[local].captures) {
      final storageType = context.fieldTypes[captureIndex];
      feOperand(opLoadLocal, 0);
      feOperand(opInt, 2 + captureIndex);
      feBuiltinTyped(bObjectGet, 2, storageType);
      final slot = feTemp(storageType);
      feOperand(opStoreLocal, slot);
      feBindLocal(capture.binding, capture.type, slot);
      feFlow.types[capture.binding] = capture.promoted;
      feFlow.assignments[capture.binding] = capture.assignment;
      final declaration = bindingDeclaration(feBindings, capture.binding);
      if (declaration.lateVariable &&
          declaration.written &&
          capture.assignment != flowAssigned)
        feFlow.assignments[capture.binding] = flowMaybeAssigned;
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
  feFunction = 0;
  feCatches = <FeCatch>[];
  feFinalizers = <FeFinally>[];
  ir.clear();
  irTypes.clear();
  functions.clear();
  genericCalls.clear();
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
  feOwnMembers = <ClassMembers>[];
  feClassOrder = <int>[];
  feDispatches.clear();
  feClassFieldStarts.clear();
  feFieldNodes.clear();
  feFieldBindings.clear();
  feClassFieldCounts.clear();
  feClassConstructors.clear();
  feConstructorPlans.clear();
  feFieldTypes.clear();
  feFieldIndices.clear();
  feLateFieldStates.clear();
  feLateFieldGetters.clear();
  feLateFieldSetters.clear();
  feLateFunctionFields.clear();
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
  feLateLocals = List<FeLateLocal?>.filled(feBindings.variables.length, null);
  feFlow = .create(0);
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
  feLateFunctionFields.add(-1);
  feConstructors.add(0);
  feSources = source;
  entrySource = source.entry;
  entryFunction = -1;
  feSymbols = SymbolTable(source, <DeclarationSymbol>[]);
  feTokens = source.tokens;
  feAt = 0;
  feRuntimeTokens = source.runtimeTokens;
  final paths = <String>[for (var file in source.files) file.path];
  final syntax = parseUnit(
    Parser(feTokens, 0, 0, paths),
    <bool>[for (var file in source.files) file.languageMajor >= 3],
    <bool>[
      for (var file in source.files)
        file.languageMajor > 3 ||
            file.languageMajor == 3 && file.languageMinor >= 13,
    ],
  );
  feInstallSymbols();
  feCollectDeclarations(syntax);
  feObjectMembers = ClassMembers(<MemberBinding>[]);
  final objectSymbol = symbolOwnDeclaration(feSymbols, sourceCore, 'Object');
  for (final signature
      in feSymbols.declarations[objectSymbol].instanceMembers) {
    if (signature.implementation == '') continue;
    final symbol = symbolOwnDeclaration(feSymbols, 0, signature.implementation);
    if (symbol < 0) continue;
    final member = MemberBinding(signature.name, sourceCore);
    member.receiverParameter = true;
    member.method = feSymbols.declarations[symbol].target;
    feObjectMembers.members.add(member);
  }
  feOwnMembers = feMembers;
  feConstants = ConstantContext(feSymbols, feGlobalNodes, globalTypes);
  feConstants.classConstructors = feClassConstructors;
  feConstants.globalOwners = feGlobalOwners;
  feConstants.identical = symbolOwnDeclaration(
    feSymbols,
    sourceCore,
    'identical',
  );
  feMembers = checkClassInterfaces(
    feSymbols,
    feClassNodes,
    feClassOrder,
    feOwnMembers,
    feObjectMembers,
    feFunctionNodes,
    feFieldTypes,
    feFieldNodes,
    feConstants,
  );
  for (var f = 1; f < feFunctionNodes.length; f++) {
    if (!feFunctionNodes[f].primary) continue;
    final parameters = feFunctionNodes[f].parameters;
    for (var p = 0; p < parameters.length; p++)
      if (parameters[p].fieldFormal && parameters[p].type.name == '')
        functions[f].parameterTypes[p + 1] =
            feFieldTypes[feField(
              feOwners[f],
              parameters[p].name,
              parameters[p].token,
            )];
  }
  for (final owner in feClassOrder) {
    final parent = classSuperclasses[owner];
    var prefix = 0;
    if (typeIsClass(parent)) {
      final base = typeArgument(parent);
      prefix = (classSizes[base] - objectHeaderBytes) ~/ 8;
      classPointerMasks[owner] = <int>[...classPointerMasks[base]];
      classTaggedMasks[owner] = <int>[...classTaggedMasks[base]];
    }
    classSizes[owner] += prefix * 8;
    final slots = (classSizes[owner] - objectHeaderBytes) ~/ 8;
    while (classPointerMasks[owner].length * 64 < slots) {
      classPointerMasks[owner].add(0);
      classTaggedMasks[owner].add(0);
    }
    for (var index = 0; index < feClassFieldCounts[owner]; index++) {
      final field = feClassFieldStarts[owner] + index;
      final slot = prefix + index;
      feFieldIndices[field] = slot;
      if (feLateFieldStates[field] >= 0) feLateFieldStates[field] += prefix;
      if (typeIsReference(feFieldTypes[field]))
        classPointerMasks[owner][slot ~/ 64] |= 1 << (slot & 63);
      if (typeIsTagged(feFieldTypes[field]))
        classTaggedMasks[owner][slot ~/ 64] |= 1 << (slot & 63);
    }
    final rendered = classImplementation(
      owner,
      'toString',
      sourceCore,
      classMethod,
      feOwnMembers,
      feObjectMembers,
      feFunctionNodes,
    );
    classToStringFunctions[owner] =
        rendered == null || rendered.receiverParameter ? -1 : rendered.method;
  }
  checkInitializers(feSymbols, syntax);
  var plannedFunction = 0;
  while (plannedFunction < functions.length) {
    var plan = const ConstructorPlan(<ConstructorStep>[], -1);
    if (feConstructors[plannedFunction] == 1) {
      final owner = feOwners[plannedFunction];
      plan = planConstructorInitializers(
        feSymbols,
        owner,
        feClassNodes,
        feFunctionNodes[plannedFunction],
        feOwnMembers,
        feClassFieldStarts[owner],
        feClassConstructors,
        feFunctionNodes,
      );
    }
    if (feConstructors[plannedFunction] == 2 &&
        feFunctionNodes[plannedFunction].factoryRedirect != null)
      plan = ConstructorPlan(
        const <ConstructorStep>[],
        feFactoryRedirectTarget(plannedFunction),
      );
    feConstructorPlans.add(plan);
    plannedFunction++;
  }
  checkConstructorRedirects(feSymbols, feFunctionNodes, feConstructorPlans);
  resolveSuperParameters(
    feSymbols,
    feFunctionNodes,
    functions,
    feConstructorPlans,
    feClassConstructors,
    feClassOrder,
  );
  feCheckFactoryRedirects();
  var sourceFunctions = functions.length;
  final bodyBindings = <FunctionBindings>[];
  final localTypeScopes = <List<int>>[];
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
        feConstructorPlans[bindingFunction].superCall,
        feFunctionNodes[bindingFunction].primary
            ? feClassNodes[feOwners[bindingFunction]].fields
            : const <AstVariable>[],
      ),
    );
    while (localTypeScopes.length < feLocalFunctions.length)
      localTypeScopes.add(functions[bindingFunction].typeParameters);
    while (feLocalOwners.length < feLocalFunctions.length)
      feLocalOwners.add(feOwners[bindingFunction]);
    bindingFunction++;
  }
  feRegisterConstructorConstants();
  feResolvePragma();
  feCheckUnitMetadata(syntax);
  var constant = 0;
  while (constant < feGlobalNodes.length) {
    if (feGlobalNodes[constant].modifier == 'const') {
      final value = evaluateGlobalConstant(feConstants, constant);
      globalTypes[constant] = value.type;
      if (value.type == value.kind &&
          (value.kind == tInt ||
              value.kind == tDouble ||
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
    final marker = symbolOwnDeclaration(feSymbols, 0, 'rtAbiVersion');
    if (marker < 0 || feSymbols.declarations[marker].kind != symbolGlobal) {
      sourceError(
        feSources,
        feSources.files[0].tokens[0],
        'runtime must declare const int rtAbiVersion = ' +
            runtimeAbiVersion.toString(),
      );
    }
    final global = feSymbols.declarations[marker].target;
    if (_feLiteralTypes[global] != tInt ||
        _feLiteralValues[global] != runtimeAbiVersion) {
      feAstError(
        feGlobalNodes[global].token,
        'runtime rtAbiVersion must be const int ' +
            runtimeAbiVersion.toString(),
      );
    }
  }
  final initializerBindings = <FunctionBindings>[];
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
    final end = field + feClassFieldCounts[owner];
    while (field < end) {
      feFieldBindings.add(
        feFieldNodes[field].lateVariable || feClassNodes[owner].hasPrimary
            ? FunctionBindings(<LocalVariable>[], -1)
            : feBindInitializer(feFieldNodes[field], owner),
      );
      field++;
    }
    owner++;
  }
  feLocalStart = sourceFunctions;
  var local = 0;
  while (local < feLocalFunctions.length) {
    final declaration = feLocalFunctions[local];
    final function = feRegisterFunction(
      declaration.syntax,
      -1,
      false,
      true,
      local < localTypeScopes.length ? localTypeScopes[local] : const <int>[],
    );
    final info = functions[function];
    for (var binding in declaration.body!.captures) {
      if (declaration.body!.variables[binding].function != local) {
        info.closureLayout ??= ClosureLayout(<int>[]);
        break;
      }
    }
    if (info.closureLayout != null) {
      info.parameterTypes.insert(0, tFunction);
      info.parameters++;
      info.locals++;
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
  final sourceGlobals = globalNames.length;
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
      final type = feLowerInitializer(
        feGlobalNodes[i],
        feGlobalInitializers[i].bindings,
        globalTypes[i],
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
  functions[0].end = ir.length;
  var f = 1;
  while (f < sourceFunctions) {
    functions[f].start = ir.length;
    feBeginFunction(f, bodyBindings[f]);
    final functionSyntax = feFunctionNodes[f];
    final expression = functionSyntax.arrow;
    if (feLateFunctionFields[f] >= 0) {
      feLowerLateField(f, feLateFunctionFields[f]);
    } else if (feConstructors[f] == 1) {
      feLowerConstructor(f);
    } else if (functionSyntax.factoryRedirect != null) {
      feEmit(opUnreachable);
    } else if (feHasReceiver(f) &&
        functionSyntax.body == null &&
        expression == null) {
      feEmit(opUnreachable);
    } else if (expression != null) {
      if (feInfersLocalResult(f)) {
        final type = feLowerAssignedValue(expression, feLocalResultContext(f));
        feConvertValue(type, functions[f].result, expression.token);
      } else {
        feLowerInContext(expression, functions[f].result);
      }
      feEmit(opReturn);
    } else {
      final body = functionSyntax.body;
      if (body != null) feLowerStatement(body);
      final result = functions[f].result;
      if (feFlow.reachable && !typeIsSubtype(tNull, result)) {
        feAstError(
          functionSyntax.token,
          'non-nullable function may complete without returning',
        );
      }
      if (feFlow.reachable) {
        feInteger(0, tNull);
        feConvertValue(tNull, result, functionSyntax.token);
        feEmit(opReturn);
      } else {
        feEmit(opUnreachable);
      }
    }
    functions[f].locals = feNextLocal;
    functions[f].localTypes = feSlotTypes;
    functions[f].end = ir.length;
    f++;
  }
  feConstants.lexicalClass = -1;
  feGenerateGlobals(sourceGlobals);
  feGenerateDispatches();
  if (imageKind == 0)
    feGenerateEntry();
  else
    feGenerateConstantObjects();
  feGenerateCallableAdapters();
}

const int classTearoff = 3;

class FeDispatch {
  final int function;
  final int owner;
  final MemberBinding member;
  final int role;
  final ClassSignature signature;
  final List<int> supplied;

  FeDispatch(
    this.function,
    this.owner,
    this.member,
    this.role,
    this.signature,
    this.supplied,
  );
}

List<FeDispatch> feDispatches = <FeDispatch>[];

bool feNeedsDispatch(int owner) => owner >= 0 && feClassPolymorphic[owner];

int feDispatchMember(
  int owner,
  MemberBinding member,
  int role,
  List<int> supplied,
) {
  for (final dispatch in feDispatches) {
    if (dispatch.owner != owner ||
        dispatch.member != member ||
        dispatch.role != role ||
        dispatch.supplied.length != supplied.length)
      continue;
    var same = true;
    for (var i = 0; i < supplied.length; i++)
      if (supplied[i] != dispatch.supplied[i]) same = false;
    if (same) return dispatch.function;
  }
  final signature = classSignature(
    member,
    role == classTearoff ? classMethod : role,
    feFunctionNodes,
    feFieldTypes,
  );
  final function = functions.length;
  final typeParameters = <int>[];
  if (role != classTearoff)
    for (var i = 0; i < signature.typeParameters.length; i++) {
      final parameter = typeParameterInfo(signature.typeParameters[i]);
      typeParameters.add(
        newTypeParameter(
          -function - 1,
          i,
          parameter.name,
          parameter.bindsName,
          parameter.hasBound,
        ),
      );
    }
  for (var i = 0; i < typeParameters.length; i++)
    typeParameterInfo(typeParameters[i]).bound = substituteType(
      typeParameterInfo(signature.typeParameters[i]).bound,
      signature.typeParameters,
      typeParameters,
    );
  final parameters = <int>[classType(owner)];
  if (typeParameters.isNotEmpty) parameters.add(listType(tObject));
  for (final index in supplied)
    parameters.add(
      substituteType(
        signature.parameters[index],
        signature.typeParameters,
        typeParameters,
      ),
    );
  final result = role == classTearoff
      ? feCallableType(member.method, feClassNodes[owner].token)
      : substituteType(
          signature.result,
          signature.typeParameters,
          typeParameters,
        );
  final info = FunctionInfo(
    '#dispatch:' + classNames[owner] + '.' + member.name,
    0,
    parameters.length,
    parameters.length,
    result,
    parameters,
    <int>[],
    feClassSources[owner],
  );
  info.typeParameters = typeParameters;
  if (typeParameters.isNotEmpty) info.typeEnvironment = 1;
  functions.add(info);
  feDispatches.add(
    FeDispatch(function, owner, member, role, signature, supplied),
  );
  return function;
}

int feDispatchMethod(int function, AstExpression call) {
  final syntax = feFunctionNodes[function];
  final owner = feOwners[function];
  final member =
      feMembers[owner].members[lookupMember(
        feMembers[owner],
        syntax.name,
        sourceLibrary(feSources, feTokens[syntax.token].source),
      )];
  final bindings = bindArguments(feSources, syntax, call, 1);
  final present = List<bool>.filled(syntax.parameters.length, false);
  for (final parameter in bindings) present[parameter] = true;
  final supplied = <int>[];
  for (var i = 0; i < syntax.parameters.length; i++)
    if (present[i]) supplied.add(i);
  return feDispatchMember(owner, member, classMethod, supplied);
}

void feGenerateDispatches() {
  for (final dispatch in feDispatches) {
    final info = functions[dispatch.function];
    info.start = ir.length;
    feFunction = dispatch.function;
    feSlotTypes = <int>[];
    feNextLocal = 0;
    feFlow = .create(0);
    for (final type in info.parameterTypes) feTemp(type);
    final token = feClassNodes[dispatch.owner].token;
    final receiverType = classType(dispatch.owner);
    final role = dispatch.role;
    for (var c = feClassOrder.length - 1; c >= 0; c--) {
      final owner = feClassOrder[c];
      if (feClassNodes[owner].isAbstract ||
          !typeIsSubtype(classType(owner), receiverType))
        continue;
      final memberRole = role == classTearoff ? classMethod : role;
      final member = classImplementation(
        owner,
        dispatch.member.name,
        dispatch.member.library,
        memberRole,
        feOwnMembers,
        feObjectMembers,
        feFunctionNodes,
      )!;
      if (role == classTearoff && member.receiverParameter)
        feAstError(token, 'Object method tear-offs are not yet supported');
      feOperand(opLoadLocal, 0);
      feConvertValue(receiverType, tDynamic, token);
      feOperand(opTypeTest, classType(owner));
      final next = feJump(opJumpFalse);
      feFlow = .create(0);
      feOperand(opLoadLocal, 0);
      feNarrowValue(receiverType, classType(owner));
      var result = tVoid;
      if (role == classTearoff) {
        result = feCreateBoundMethod(member.method, token, true);
      } else {
        final function = classMemberFunction(member, role);
        if (function < 0) {
          final field = role == classGetter ? member.field : member.fieldSetter;
          if (role == classGetter) {
            if (feLateFieldGetters[field] >= 0)
              feCall(feLateFieldGetters[field], 1);
            else {
              feOperand(opInt, feFieldIndices[field]);
              feBuiltinTyped(bObjectGet, 2, feFieldTypes[field]);
            }
            result = feFieldTypes[field];
          } else {
            if (feLateFieldSetters[field] < 0)
              feOperand(opInt, feFieldIndices[field]);
            feOperand(opLoadLocal, 1);
            feConvertValue(info.parameterTypes[1], feFieldTypes[field], token);
            if (feLateFieldSetters[field] >= 0)
              feCall(feLateFieldSetters[field], 2);
            else
              feBuiltinTyped(bObjectSet, 3, feFieldTypes[field]);
            feEmit(opPop);
            feInteger(0, tVoid);
          }
        } else {
          final target = functions[function];
          feConvertValue(classType(owner), target.parameterTypes[0], token);
          final formals = member.receiverParameter
              ? feFunctionNodes[function].parameters.sublist(1)
              : feFunctionNodes[function].parameters;
          final generic = target.typeParameters.isNotEmpty;
          final offset = generic ? 2 : 1;
          if (generic) feOperand(opLoadLocal, 1);
          for (var p = 0; p < formals.length; p++) {
            var slot = -1;
            for (var i = 0; i < dispatch.supplied.length; i++) {
              final supplied = dispatch.supplied[i];
              if (correspondingParameter(
                    formals,
                    dispatch.signature.formals[supplied],
                    supplied,
                  ) ==
                  p)
                slot = i + offset;
            }
            final declared = target.parameterTypes[offset + p];
            final expected = substituteType(
              declared,
              target.typeParameters,
              info.typeParameters,
            );
            if (slot >= 0) {
              feOperand(opLoadLocal, slot);
              feConvertValue(info.parameterTypes[slot], expected, token);
            } else {
              feConstantValue(
                feParamDefaults[function][offset + p],
                expected,
                token,
              );
            }
            if (generic)
              feConvertValue(expected, genericBoundaryType(declared), token);
          }
          if (generic) {
            final invocation = genericCalls.length;
            genericCalls.add(GenericCall(function, info.typeParameters));
            result = feFinishGenericCall(invocation, token);
          } else {
            feCall(function, target.parameters);
            result = target.result;
          }
        }
      }
      feConvertValue(result, info.result, token);
      feEmit(opReturn);
      fePatch(next, ir.length);
    }
    feEmit(opUnreachable);
    info.locals = feNextLocal;
    info.localTypes = feSlotTypes;
    info.end = ir.length;
  }
}

void feGenerateCallableAdapters() {
  final targets = functions.length;
  var target = 0;
  while (target < targets) {
    final info = functions[target];
    if (info.callableAdapter == -2) {
      final parameters = <int>[tFunction];
      final offset = info.closureLayout == null ? 0 : 1;
      var p = offset;
      while (p < info.parameterTypes.length) {
        parameters.add(tDynamic);
        p++;
      }
      final adapter = functions.length;
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
      functions[adapter].closureLayout = info.closureLayout;
      feFunction = adapter;
      feFlow = .create(0);
      feSlotTypes = <int>[];
      feNextLocal = 0;
      p = 0;
      while (p < parameters.length) {
        feTemp(parameters[p]);
        p++;
      }
      final token = feFunctionNodes[target].token;
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
      functions[adapter].end = ir.length;
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
  var info = functions[main];
  var offset = feParameterOffset(main);
  var generic = info.typeParameters.isNotEmpty;
  var typeArguments = instantiateTypeParameters(info.typeParameters);
  for (var i = 0; i < typeArguments.length; i++) {
    var bound = substituteType(
      typeParameterInfo(info.typeParameters[i]).bound,
      info.typeParameters,
      typeArguments,
    );
    if (!typeIsSubtype(typeArguments[i], bound))
      feAstError(
        syntax.token,
        'main type arguments do not satisfy function bounds',
      );
  }
  var parameters = syntax.parameters;
  if (generic && parameters.isNotEmpty)
    feAstError(
      syntax.token,
      'generic main with value parameters is not yet supported',
    );
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
      !typingAssignable(argumentsType, info.parameterTypes[offset]))
    feAstError(
      parameters[0].token,
      'first main parameter must accept List<String>',
    );
  var supplied = positional;
  if (supplied > 2) supplied = 2;
  p = supplied;
  while (p < parameters.length) {
    var value = feParamDefaults[main][offset + p];
    if (typeIsList(value.kind) || typeIsClass(value.kind))
      feConstantGetter(value);
    p++;
  }
  feGenerateConstantObjects();
  entryFunction = main;
  if (!generic && parameters.length <= 1 && parameters.length == positional)
    return;
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
  if (generic) feLoadTypeEnvironment(typeArguments);
  p = 0;
  while (p < parameters.length) {
    var declared = info.parameterTypes[offset + p];
    var expected = substituteType(declared, info.typeParameters, typeArguments);
    if (p < supplied) {
      var actual = tNull;
      if (p == 0) {
        feOperand(opLoadLocal, 0);
        actual = argumentsType;
      } else {
        feInteger(0, tNull);
      }
      if (typeIsSubtype(actual, expected)) {
        feConvertValue(actual, expected, parameters[p].token);
      } else {
        feConvertValue(actual, tDynamic, parameters[p].token);
        feBuiltinTyped(bValueCast, 1, expected);
      }
    } else {
      feConstantValue(
        feParamDefaults[main][offset + p],
        expected,
        syntax.token,
      );
    }
    if (generic) {
      var boundary = genericBoundaryType(declared);
      if (expected == tVoid && boundary == tDynamic)
        feBuiltinTyped(bBoxRef, 1, boundary);
      else
        feConvertValue(expected, boundary, syntax.token);
    }
    p++;
  }
  if (generic) {
    var invocation = genericCalls.length;
    genericCalls.add(GenericCall(main, typeArguments));
    feFinishGenericCall(invocation, syntax.token);
  } else
    feCall(main, parameters.length);
  feEmit(opPop);
  feInteger(0, tVoid);
  feEmit(opReturn);
  functions[entryFunction].locals = feNextLocal;
  functions[entryFunction].localTypes = feSlotTypes;
  functions[entryFunction].end = ir.length;
}

void feRefreshLoopBinding(int binding) {
  if (feCellBinding(binding)) {
    feLoadLocalStorage(binding);
    feAllocateCell(feBindingTypes[binding]);
    feOperand(opStoreLocal, feBindingSlots[binding]);
  }
}

void feRefreshPatternBindings(AstPattern pattern) {
  if (pattern.binding >= 0) feRefreshLoopBinding(pattern.binding);
  for (var child in pattern.children) feRefreshPatternBindings(child);
  for (var field in pattern.fields) feRefreshPatternBindings(field.pattern);
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
  var exitFlow = FlowState.copy(feFlow);
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
    var initial = statement.children[0];
    for (var variable in initial.variables)
      feRefreshLoopBinding(variable.binding);
    if (initial.patternDeclaration case final declaration?)
      feRefreshPatternBindings(declaration.pattern);
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
  var pattern = statement.patternDeclaration;
  var context = -1;
  if (declaration != null) {
    feCheckMetadata(declaration.metadata, feLexicalOwner(feFunction));
    if (declaration.type.name != '')
      context = listType(feResolveType(declaration.type));
  }
  if (pattern != null) {
    feCheckMetadata(pattern.metadata, feLexicalOwner(feFunction));
    context = listType(
      patternContextType(feConstants, pattern.pattern, feBindingTypes),
    );
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
  if (context >= 0 && pattern == null) type = typeArgument(context);
  var cell = declaration != null && feCellBinding(declaration.binding);
  var variable = -1;
  if (declaration != null) {
    variable = feTemp(cell ? tObject : type);
    feBindLocal(declaration.binding, type, variable);
  }
  feFlow = flowSplit(feFlow);
  feLoopFlow(statement);
  var exitFlow = FlowState.copy(feFlow);
  if (declaration != null) flowDeclare(feFlow, declaration.binding, type, true);
  var repeat = ir.length;
  feOperand(opLoadLocal, iterable);
  feBuiltin(bListLength, 1);
  feOperand(opLoadLocal, length);
  feEmit(opEq);
  var unchanged = feJump(opJumpTrue);
  final iterationFlow = feFlow;
  feFlow = .copy(iterationFlow);
  feCall(feFindFunction('rtListModificationError'), 0);
  feEmit(opUnreachable);
  fePatch(unchanged, ir.length);
  feFlow = iterationFlow;
  feOperand(opLoadLocal, index);
  feOperand(opLoadLocal, length);
  feEmit(opLt);
  var done = feJump(opJumpFalse);
  feOperand(opLoadLocal, iterable);
  feOperand(opLoadLocal, index);
  feBuiltinTyped(bListGet, 2, element);
  if (pattern != null) {
    feLowerDestructure(pattern.pattern, element);
    feEmit(opPop);
  } else if (declaration != null) {
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

void feCheckPatternTargets(AstPattern syntax) {
  if (syntax.kind == patternAssignedVariable) {
    feLocalSlot(syntax.binding, syntax.token);
    if (feBindings.variables[syntax.binding].constant)
      feAstError(syntax.token, 'cannot assign a constant');
  }
  for (var child in syntax.children) feCheckPatternTargets(child);
  for (var field in syntax.fields) feCheckPatternTargets(field.pattern);
}

void feLowerDestructure(AstPattern syntax, int type) {
  var value = feTemp(type);
  feOperand(opStoreLocal, value);
  var pattern = checkPattern(
    feConstants,
    syntax,
    type,
    feBindingTypes,
    feCheckMemberRead,
    true,
  );
  fePatternVariables(pattern);
  var cache = <PatternReadCache>[];
  fePatternCacheKeys(cache, syntax, -1);
  fePatternCacheInitialize(cache);
  var failed = <int>[];
  feLowerPattern(pattern, value, failed, cache, -1);
  if (failed.isNotEmpty) {
    var matched = feFlow;
    var done = feJump(opJump);
    fePatchJumps(failed, ir.length);
    feFlow = .copy(feFlow);
    feCall(feFindFunction('rtPatternMatchFailure'), 0);
    feEmit(opUnreachable);
    fePatch(done, ir.length);
    feFlow = matched;
  }
  fePatternCells(pattern);
  feOperand(opLoadLocal, value);
}

int feLowerPatternAssignment(AstExpression expression) {
  var pattern = expression.pattern!;
  feCheckPatternTargets(pattern);
  var context = patternContextType(feConstants, pattern, feBindingTypes);
  var type = feLowerAssignedValue(expression.children[0], context);
  feLowerDestructure(pattern, type);
  return type;
}

void fePatternVariables(CheckedPattern pattern) {
  var binding = pattern.syntax.binding;
  if (binding >= 0 &&
      pattern.syntax.kind != patternAssignedVariable &&
      feBindingSlots[binding] < 0)
    feBindLocal(binding, pattern.variableType, feTemp(pattern.variableType));
  for (var child in pattern.children) fePatternVariables(child);
}

void fePatternCells(CheckedPattern pattern) {
  var binding = pattern.syntax.binding;
  if (binding >= 0 &&
      pattern.syntax.kind != patternAssignedVariable &&
      feCellBinding(binding)) {
    feOperand(opLoadLocal, feBindingSlots[binding]);
    feAllocateCell(pattern.variableType);
    var cell = feTemp(tObject);
    feBindingSlots[binding] = cell;
    feOperand(opStoreLocal, cell);
  }
  if (pattern.syntax.kind == patternOr)
    fePatternCells(pattern.children[0]);
  else
    for (var child in pattern.children) fePatternCells(child);
}

int fePatternReadKey(
  List<PatternReadCache> cache,
  int parent,
  String name, [
  int first = -1,
  int second = -1,
]) {
  for (var i = 0; i < cache.length; i++)
    if (cache[i].parent == parent &&
        cache[i].name == name &&
        cache[i].first == first &&
        cache[i].second == second)
      return i;
  return -1;
}

int fePatternCacheKey(
  List<PatternReadCache> cache,
  int parent,
  String name, [
  int first = -1,
  int second = -1,
]) {
  var key = fePatternReadKey(cache, parent, name, first, second);
  if (key < 0) {
    key = cache.length;
    cache.add(PatternReadCache(parent, name, first, second));
  } else
    cache[key].uses++;
  return key;
}

void fePatternCacheKeys(
  List<PatternReadCache> cache,
  AstPattern syntax,
  int parent,
) {
  if (syntax.kind == patternList) {
    var rest = patternListRest(syntax);
    var count = syntax.children.length - (rest >= 0 ? 1 : 0);
    if (rest < 0 || count > 0) fePatternCacheKey(cache, parent, 'length');
    for (var i = 0; i < syntax.children.length; i++) {
      var child = syntax.children[i];
      var key = -1;
      if (i == rest) {
        if (child.children.isEmpty || patternSkipsRead(child.children[0]))
          continue;
        key = fePatternCacheKey(cache, parent, 'sublist()', rest, count - rest);
        child = child.children[0];
      } else {
        if (patternSkipsRead(child)) continue;
        key = rest >= 0 && i > rest
            ? fePatternCacheKey(
                cache,
                parent,
                'tail[]',
                syntax.children.length - i - 1,
              )
            : fePatternCacheKey(cache, parent, '[]', i);
      }
      fePatternCacheKeys(cache, child, key);
    }
    return;
  }
  for (var field in syntax.fields) {
    var key = fePatternCacheKey(cache, parent, field.name);
    fePatternCacheKeys(cache, field.pattern, key);
  }
  for (var child in syntax.children) fePatternCacheKeys(cache, child, parent);
}

void fePatternCacheInitialize(List<PatternReadCache> cache) {
  for (var read in cache) {
    if (read.uses > 1) {
      read.slot = feTemp(tDynamic);
      feInteger(0, tNull);
      feConvertValue(tNull, tDynamic, feAt);
      feOperand(opStoreLocal, read.slot);
      read.ready = feTemp(tBool);
      feInteger(0, tBool);
      feOperand(opStoreLocal, read.ready);
    }
  }
}

int fePatternReadStart(PatternReadCache cache) {
  var done = -1;
  if (cache.ready >= 0) {
    feOperand(opLoadLocal, cache.ready);
    done = feJump(opJumpTrue);
  }
  return done;
}

int fePatternReadFinish(PatternReadCache cache, int type, int done, int token) {
  if (cache.ready < 0) {
    cache.slot = feTemp(type);
    feOperand(opStoreLocal, cache.slot);
  } else {
    feCallableBox(type, token);
    feOperand(opStoreLocal, cache.slot);
    feInteger(1, tBool);
    feOperand(opStoreLocal, cache.ready);
    fePatch(done, ir.length);
  }
  return fePatternSlot(cache.slot, type, token);
}

int fePatternMemberRead(
  PatternReadCache cache,
  CheckedMemberRead member,
  int value,
  int token,
) {
  var done = fePatternReadStart(cache);
  fePatternRead(value, member.receiver, token);
  feReadCheckedMember(member, token);
  return fePatternReadFinish(cache, member.type, done, token);
}

int fePatternListRead(
  PatternReadCache cache,
  int type,
  int value,
  int length,
  int token,
) {
  var done = fePatternReadStart(cache);
  fePatternRead(value, type, token);
  var result = typeArgument(type);
  if (cache.name == 'sublist()') {
    feOperand(opInt, cache.first);
    if (cache.second > 0) {
      feOperand(opLoadLocal, length);
      feOperand(opInt, cache.second);
      feEmit(opSub);
    } else
      feOperand(opInt, 0);
    feOperand(opInt, cache.second > 0 ? 1 : 0);
    result = type;
    feBuiltinTyped(bListSublist, 4, result);
  } else {
    if (cache.name == 'tail[]') {
      feOperand(opLoadLocal, length);
      feOperand(opInt, cache.first + 1);
      feEmit(opSub);
    } else
      feOperand(opInt, cache.first);
    feBuiltinTyped(bListGet, 2, result);
  }
  return fePatternReadFinish(cache, result, done, token);
}

FlowState feIfConditionJumps(AstExpression condition, List<int> failed) {
  if (condition.kind != astIfCaseCondition)
    return feConditionJumps(condition, false, failed);
  var source = condition.children[0];
  var type = feLowerExpression(source);
  var value = feTemp(type);
  feOperand(opStoreLocal, value);
  var cache = <PatternReadCache>[];
  fePatternCacheKeys(cache, condition.pattern!, -1);
  fePatternCacheInitialize(cache);
  feConstants.localTypes = feFlow.types;
  var pattern = checkPattern(
    feConstants,
    condition.pattern!,
    type,
    feBindingTypes,
    feCheckMemberRead,
  );
  fePatternVariables(pattern);
  var otherwise = FlowState.copy(feFlow);
  var binding = source.kind == astName ? source.binding : -1;
  if (binding >= 0 && !fePromotable(binding)) binding = -1;
  if (pattern.remaining == tNever)
    flowUnreachable(otherwise);
  else if (binding >= 0)
    flowPromote(otherwise, binding, pattern.remaining);
  feLowerPattern(pattern, value, failed, cache, -1);
  fePatternCells(pattern);
  if (binding >= 0) flowPromote(feFlow, binding, pattern.matched);
  if (condition.children.length == 2)
    otherwise = feJoinFlow(
      otherwise,
      feConditionJumps(condition.children[1], false, failed),
    );
  return otherwise;
}

void feLowerPattern(
  CheckedPattern pattern,
  int value,
  List<int> failed,
  List<PatternReadCache> cache,
  int parent,
) {
  var syntax = pattern.syntax;
  var kind = syntax.kind;
  var token = syntax.token;
  if (kind == patternVariable ||
      kind == patternAssignedVariable ||
      kind == patternObject ||
      kind == patternList) {
    if (pattern.castInput) {
      feOperand(opLoadLocal, value);
      feOperand(opTypeCast, pattern.tested);
      value = feTemp(pattern.tested);
      feOperand(opStoreLocal, value);
    } else if (pattern.tested >= 0 &&
        !typeIsSubtype(pattern.input, pattern.tested)) {
      if (typeIsSubtype(typingNonNull(pattern.input), pattern.tested)) {
        failed.add(feJumpIfNull(value));
      } else {
        fePatternRead(value, pattern.input, token);
        feCallableBox(pattern.input, token);
        feOperand(opTypeTest, pattern.tested);
        failed.add(feJump(opJumpFalse));
      }
    }
    if (kind == patternList) {
      var rest = patternListRest(syntax);
      var count = syntax.children.length - (rest >= 0 ? 1 : 0);
      var length = -1;
      if (rest < 0 || count > 0) {
        var key = fePatternReadKey(cache, parent, 'length');
        length = fePatternMemberRead(
          cache[key],
          CheckedMemberRead(pattern.tested, tInt, memberReadLength, -1),
          value,
          token,
        );
        feOperand(opLoadLocal, length);
        feOperand(opInt, count);
        feEmit(
          rest >= 0
              ? opGe
              : count == 0
              ? opLe
              : opEq,
        );
        failed.add(feJump(opJumpFalse));
      }
      for (var i = 0; i < pattern.children.length; i++) {
        var child = pattern.children[i];
        var key = -1;
        if (i == rest) {
          if (child.children.isEmpty ||
              patternSkipsRead(child.children[0].syntax))
            continue;
          key = fePatternReadKey(
            cache,
            parent,
            'sublist()',
            rest,
            count - rest,
          );
          child = child.children[0];
        } else {
          if (patternSkipsRead(child.syntax)) continue;
          key = rest >= 0 && i > rest
              ? fePatternReadKey(
                  cache,
                  parent,
                  'tail[]',
                  pattern.children.length - i - 1,
                )
              : fePatternReadKey(cache, parent, '[]', i);
        }
        var element = fePatternListRead(
          cache[key],
          pattern.tested,
          value,
          length,
          child.syntax.token,
        );
        feLowerPattern(child, element, failed, cache, key);
      }
    } else if (kind == patternObject) {
      for (var i = 0; i < pattern.fields.length; i++) {
        var field = syntax.fields[i];
        var key = fePatternReadKey(cache, parent, field.name);
        var member = fePatternMemberRead(
          cache[key],
          pattern.fields[i],
          value,
          field.token,
        );
        feLowerPattern(pattern.children[i], member, failed, cache, key);
      }
    } else {
      var binding = syntax.binding;
      if (binding >= 0) {
        fePatternRead(value, pattern.variableType, token);
        if (kind == patternAssignedVariable) {
          var target = FeLvalue(pattern.variableType, 0, -1, -1, binding, -1);
          feWriteLvalue(target, token);
          feWriteFlow(target, pattern.variableType);
          feEmit(opPop);
        } else {
          feOperand(opStoreLocal, feBindingSlots[binding]);
          flowDeclare(feFlow, binding, pattern.variableType, true);
        }
      }
    }
  } else if (kind == patternAnd) {
    var left = pattern.children[0];
    feLowerPattern(left, value, failed, cache, parent);
    var right = pattern.children[1];
    feLowerPattern(
      right,
      fePatternSlot(value, right.input, token),
      failed,
      cache,
      parent,
    );
  } else if (kind == patternOr) {
    var before = FlowState.copy(feFlow);
    var other = <int>[];
    feLowerPattern(pattern.children[0], value, other, cache, parent);
    var leftFlow = feFlow;
    var done = feJump(opJump);
    fePatchJumps(other, ir.length);
    feFlow = before;
    var right = pattern.children[1];
    feLowerPattern(
      right,
      fePatternSlot(value, right.input, token),
      failed,
      cache,
      parent,
    );
    feFlow = feJoinFlow(leftFlow, feFlow);
    fePatch(done, ir.length);
  } else if (kind == patternNullCheck) {
    failed.add(feJumpIfNull(value));
    var inner = pattern.children[0];
    feLowerPattern(
      inner,
      fePatternSlot(value, inner.input, token),
      failed,
      cache,
      parent,
    );
  } else if (kind == patternCast || kind == patternNullAssert) {
    fePatternRead(value, pattern.input, token);
    feCallableBox(pattern.input, token);
    var checked = pattern.tested;
    if (kind == patternNullAssert && typeCanBeNull(checked)) checked = tObject;
    feOperand(opTypeCast, checked);
    feConvertValue(checked, pattern.tested, token);
    var slot = feTemp(pattern.tested);
    feOperand(opStoreLocal, slot);
    feLowerPattern(pattern.children[0], slot, failed, cache, parent);
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
  var cache = <PatternReadCache>[];
  for (var arm in expression.arms) fePatternCacheKeys(cache, arm.pattern, -1);
  fePatternCacheInitialize(cache);
  feFlow = flowSplit(feFlow);
  var exitFlow = FlowState.copy(feFlow);
  flowUnreachable(exitFlow);
  var slots = <int>[];
  var conversions = <int>[];
  var result = tNever;
  var coverage = 0;
  var lengths = <PatternLengthRange>[];
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
      feCheckMemberRead,
    );
    fePatternVariables(pattern);
    var nextFlow = FlowState.copy(feFlow);
    if (pattern.remaining == tNever) flowUnreachable(nextFlow);
    var failed = <int>[];
    feLowerPattern(
      pattern,
      fePatternSlot(value, remaining, arm.pattern.token),
      failed,
      cache,
      -1,
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
      for (var range in pattern.lengths) lengths.add(range);
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
  if (patternLengthsCover(lengths, type)) coverage |= patternSpaceOther;
  if ((coverage & required) != required)
    feAstError(expression.token, 'switch expression is not exhaustive');
  feCall(feFindFunction('rtPatternMatchFailure'), 0);
  feEmit(opUnreachable);
  var done = <int>[];
  for (var i = 0; i < slots.length; i++) {
    fePatch(conversions[i], ir.length);
    var slot = slots[i];
    feOperand(opLoadLocal, slot);
    feConvertValue(feSlotTypes[slot], result, expression.arms[i].value.token);
    done.add(feJump(opJump));
  }
  fePatchJumps(done, ir.length);
  if (slots.isEmpty) feEmit(opUnreachable);
  feFlow = flowUnsplit(exitFlow);
  return result;
}

void feSwitchSharedVariables(List<AstSwitchCase> cases, int start, int end) {
  var shared = cases[end].sharedBindings;
  for (var index = 0; index < shared.length; index++) {
    var id = shared[index];
    var declaration = feBindings.variables[id];
    var type = -1;
    for (var i = start; i <= end; i++) {
      var source = cases[i].sharedSources[index];
      if (source < 0 || cases[i].labels.isNotEmpty) {
        declaration.unavailable = true;
      } else {
        var candidate = feBindingTypes[source];
        if (type < 0) type = candidate;
        if (type != candidate ||
            declaration.finalVariable !=
                feBindings.variables[source].finalVariable)
          declaration.unavailable = true;
      }
    }
    if (!declaration.unavailable)
      feBindLocal(id, type, feTemp(feCellBinding(id) ? tObject : type));
  }
}

void feSwitchCopyBindings(AstSwitchCase branch, AstSwitchCase body) {
  for (var i = 0; i < body.sharedBindings.length; i++) {
    var target = body.sharedBindings[i];
    if (feBindings.variables[target].unavailable) continue;
    var source = branch.sharedSources[i];
    var type = feBindingTypes[target];
    feLoadLocalStorage(source);
    if (feCellBinding(target)) feAllocateCell(type);
    feOperand(opStoreLocal, feBindingSlots[target]);
    flowDeclare(feFlow, target, type, true);
    if (fePromotable(target)) feFlow.types[target] = feFlow.types[source];
  }
}

void feLowerSwitch(AstStatement statement) {
  var source = statement.expressions[0];
  var type = feLowerExpression(source);
  var value = feTemp(type);
  feOperand(opStoreLocal, value);
  var cases = statement.cases;
  var modern = sourceVersionAtLeast(
    feSources,
    feTokens[statement.token].source,
    3,
    0,
  );
  var cache = <PatternReadCache>[];
  for (var branch in cases)
    if (branch.pattern case final pattern?)
      fePatternCacheKeys(cache, pattern, -1);
  fePatternCacheInitialize(cache);
  feFlow = flowSplit(feFlow);
  var initialFlow = FlowState.copy(feFlow);
  var entries = <int>[];
  var flows = <FlowState>[];
  var labels = feLabels.length;
  var labeled = false;
  for (var branch in cases) {
    for (var name in branch.labels) {
      labeled = true;
      feLabels.add(
        ControlLabel(
          name.text,
          cases[branch.bodyIndex].token,
          false,
          <int>[],
          <int>[],
          -1,
        )..caseLabel = true,
      );
    }
  }
  var coverage = 0;
  var lengths = <PatternLengthRange>[];
  var remaining = type;
  var binding = source.kind == astName ? source.binding : -1;
  if (binding >= 0 && !fePromotable(binding)) binding = -1;
  for (var branch in cases) {
    var nextFlow = FlowState.copy(feFlow);
    var failed = <int>[];
    var syntax = branch.pattern;
    if (syntax == null) {
      coverage = patternSpaceAll;
      flowUnreachable(nextFlow);
    } else {
      feConstants.localTypes = feFlow.types;
      var pattern = checkPattern(
        feConstants,
        syntax,
        remaining,
        feBindingTypes,
        feCheckMemberRead,
      );
      if (!modern && !typeIsSubtype(pattern.constant!.type, type))
        feAstError(
          syntax.token,
          'case constant is not a subtype of the switch value',
        );
      fePatternVariables(pattern);
      if (pattern.remaining == tNever) flowUnreachable(nextFlow);
      feLowerPattern(
        pattern,
        fePatternSlot(value, remaining, syntax.token),
        failed,
        cache,
        -1,
      );
      fePatternCells(pattern);
      if (binding >= 0) flowPromote(feFlow, binding, pattern.matched);
      if (branch.guard case final guard?) {
        nextFlow = feJoinFlow(nextFlow, feConditionJumps(guard, false, failed));
        if (binding >= 0) {
          var written = <int>[];
          collectWrittenExpression(
            guard,
            List<bool>.filled(feBindingTypes.length, false),
            written,
          );
          for (var changed in written) if (changed == binding) binding = -1;
        }
      } else {
        coverage |= pattern.coverage;
        for (var range in pattern.lengths) lengths.add(range);
        if (pattern.remaining != tNever) remaining = pattern.remaining;
      }
    }
    flows.add(FlowState.copy(feFlow));
    entries.add(feJump(opJump));
    fePatchJumps(failed, ir.length);
    feFlow = nextFlow;
    if (binding >= 0) flowPromote(feFlow, binding, remaining);
  }
  if (patternLengthsCover(lengths, type)) coverage |= patternSpaceOther;
  var required = patternRequiredSpace(type);
  var complete = (coverage & required) == required;
  var alwaysExhaustive =
      type == tNull || type == tNever || typeNonNullable(type) == tBool;
  if (modern && alwaysExhaustive && !complete)
    feAstError(statement.token, 'switch statement is not exhaustive');
  // Before Dart 3 only default removes the unmatched path from flow analysis.
  if (!modern) complete = cases.isNotEmpty && cases.last.pattern == null;
  var exitFlow = FlowState.copy(feFlow);
  var unmatched = -1;
  if (complete) {
    flowUnreachable(exitFlow);
    feCall(feFindFunction('rtPatternMatchFailure'), 0);
    feEmit(opUnreachable);
  } else {
    unmatched = feJump(opJump);
  }
  var labelFlow = FlowState.copy(initialFlow);
  if (labeled) {
    var written = <int>[];
    collectWrittenStatement(
      statement,
      List<bool>.filled(feBindingTypes.length, false),
      written,
    );
    flowDemote(labelFlow, written, feBindingTypes);
  }
  var breakBase = feBreaks.length;
  feLoopBreaks.add(breakBase);
  var start = 0;
  while (start < cases.length) {
    var end = cases[start].bodyIndex;
    var body = cases[end];
    feSwitchSharedVariables(cases, start, end);
    var bodyFlow = FlowState.copy(initialFlow);
    flowUnreachable(bodyFlow);
    var jumps = <int>[];
    var hasLabel = false;
    for (var i = start; i <= end; i++) {
      fePatch(entries[i], ir.length);
      feFlow = .copy(flows[i]);
      feSwitchCopyBindings(cases[i], body);
      bodyFlow = feJoinFlow(bodyFlow, feFlow);
      jumps.add(feJump(opJump));
      if (cases[i].labels.isNotEmpty) hasLabel = true;
    }
    fePatchJumps(jumps, ir.length);
    feLabelRepeat(body.token, ir.length);
    feFlow = hasLabel ? feJoinFlow(bodyFlow, labelFlow) : bodyFlow;
    for (var child in body.body) feLowerStatement(child);
    if (!modern &&
        end + 1 < cases.length &&
        body.body.isNotEmpty &&
        feFlow.reachability.last)
      feAstError(body.token, 'switch case may fall through');
    feBreaks.add(feJump(opJump));
    feBreakFlows.add(FlowState.copy(feFlow));
    start = end + 1;
  }
  if (unmatched >= 0) fePatch(unmatched, ir.length);
  feFlow = exitFlow;
  while (feBreaks.length > breakBase) {
    fePatch(feBreaks.removeLast(), ir.length);
    feFlow = feJoinFlow(feFlow, feBreakFlows.removeLast());
  }
  feLoopBreaks.removeLast();
  while (feLabels.length > labels) {
    var label = feLabels.removeLast();
    fePatchJumps(label.continues, label.repeat);
  }
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
    if (!label.loop && !label.caseLabel)
      feAstError(statement.token, 'continue requires a loop or case label');
  } else {
    if (label.caseLabel)
      feAstError(statement.token, 'cannot break to a case label');
  }
  feCompleteJump(repeat, -1, label);
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
    if (type == tDouble) {
      feBuiltin(bDoubleToString, 1);
    } else if (type == tInt) {
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
      final member =
          feMembers[owner].members[lookupMember(feMembers[owner], 'toString')];
      feCall(
        feNeedsDispatch(owner)
            ? feDispatchMember(owner, member, classMethod, const <int>[])
            : method,
        1,
      );
    } else if (type != tString) {
      feConvertValue(type, tDynamic, part.token);
      feBuiltinTyped(bValueToString, 1, tString);
    }
    if (i > 0) feBuiltin(bStringConcat, 2);
    i++;
  }
  return tString;
}
