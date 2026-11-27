import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';
import 'package:dartc/native.dart';
import 'package:dartc/source.dart';

import 'apply_table.dart';
import 'arrays.dart';
import 'builder.dart';
import 'c_header.dart';
import 'captures.dart';
import 'classes.dart';
import 'closure.dart';
import 'closure_table.dart';
import 'constant_table.dart';
import 'creators.dart';
import 'deferred.dart';
import 'dispatch.dart';
import 'dynamic_shape.dart';
import 'dynamic_table.dart';
import 'entry.dart';
import 'exports.dart';
import 'expression.dart';
import 'field_table.dart';
import 'forwarders.dart';
import 'function_objects.dart';
import 'function_table.dart';
import 'global_table.dart';
import 'levels.dart';
import 'members.dart';
import 'native_table.dart';
import 'runtime_links.dart';
import 'runtime_needs.dart';
import 'scope.dart';
import 'statement.dart';
import 'test_table.dart';
import 'type_functions.dart';
import 'type_table.dart';
import 'types.dart';

/// Finds the functions a program needs and translates each once.
///
/// Functions, classes and selectors only grow and are bounded by the source.
final class ProgramTranslator(
  final SourceProgram program,
  @override final Target target, {
  @override required final bool checksAssertions,
}) implements ProgramScope {
  SourceUnit get _unit => program.main.units.first;
  LibraryElement get _core =>
      program.main.element.typeProvider.objectElement.library;
  late final _declarations = Declarations([
    ...program.libraries,
    ...program.sdk,
  ]);
  late final _classes = ClassTable(_declarations);
  late final _dispatch = DispatchBuilder(this, _declarations, _unit);
  late final ConstantTable _constants = ConstantTable(
    _declarations,
    _classes,
    _core,
    boxElement,
    (uri) => _links.library(uri),
    (element, type, given) => _objects.constant(element, type, given),
    (types) => _types.list(types),
    typeObject,
    _dispatch.instantiate,
  );
  late final TypeTable _types = TypeTable(this, _classes, _constants);
  late final _typeFunctions = TypeFunctions(this, _unit, _classes, _types);
  late final _closures = ClosureTable(
    this,
    _unit,
    (element) => _creators.of(element),
  );
  late final _dynamics = DynamicTable(this, _unit);
  late final _fields = FieldTable(this, _declarations, _classes);
  late final _tests = TestTable(_classes);
  late final _applications = ApplyTable(this, _unit);
  late final _forwarders = ForwarderTable(this, _declarations, _unit);
  late final _links = RuntimeLinks(program, _core, createdClass, _constants);
  late final _globals = GlobalTable(
    this,
    _declarations,
    _constants,
    _pending.add,
  );
  late final _functions = FunctionTable(this, _declarations);
  final _pending = <void Function()>[];
  final _captures = <AstNode, Captures>{};
  final _cells = <HirType, HirClass>{};

  /// The functions of closures and local variables.
  final _bodies = <HirFunction>[];
  late final _creators = CreatorTable(this, _unit);

  /// The classes of local functions and variables that are no values.
  final _localClasses = <HirClass>[];
  late final _needs = RuntimeNeeds(_links, runtime);

  HirModule translate() {
    final entry = program.main.element.entryPoint;
    if (entry == null) {
      throw CompileFailure([
        _unit.problemAt(0, 'The program has no main function.'),
      ]);
    }
    final main = _functions.of(entry);
    final start = EntryTranslator(this, _unit, entry, main)..begin();
    _translateAll();
    start.finish(_needs.eventLoop, _needs.exitCode);
    return _module(start.function, const {});
  }

  /// The program as a library, and a header for it.
  ({HirModule module, String header}) translateLibrary() {
    final exports = exportsOf(program), table = ExportTable(this);
    if (exports.isEmpty) {
      throw CompileFailure([
        _unit.problemAt(0, 'The library exports no functions.'),
      ]);
    }
    exports.forEach(table.add);
    _translateAll();
    final start = HirFunction('start', const [])
      ..define([HirBlock()..end(HirReturn())]);
    return (
      module: _module(start, table.functions),
      header: HeaderWriter(natives.types).write(exports),
    );
  }

  /// Translates all that what is translated already can reach.
  void _translateAll() {
    do {
      while (_pending.isNotEmpty) {
        _pending.removeLast()();
      }
      _addRuntime();
    } while (_dispatch.update() ||
        _closures.update() ||
        _dynamics.update(
          _dispatch.classes.where(
            (class_) => !RuntimeLinks.isRuntime(class_.library),
          ),
          _classes.classOf,
          _closures.closures,
          _functionClass,
        ) ||
        _applications.update(_closures.closures) ||
        _typeFunctions.update(_dispatch.classes, _closures.closures) ||
        _pending.isNotEmpty);
    _typeFunctions.finish();
  }

  HirModule _module(HirFunction start, Map<String, HirFunction> exports) =>
      HirModule(
        start,
        [start, ...exports.values, ..._allFunctions],
        classes: [
          ..._dispatch.classes.map(_classes.classOf),
          for (final closure in _closures.closures) closure.class_,
          ..._localClasses,
          ..._cells.values,
        ],
        dispatch: {
          ..._dispatch.result(_classes.classOf, _closures, _functionClass),
          ..._closures.dispatch,
          ..._dynamics.dispatch,
          ..._typeFunctions.dispatch,
          ..._applications.dispatch,
        },
        globals: [..._globals.globals, ...natives.globals, ...deferred.globals],
        tests: _tests.results(
          _dispatch.classes,
          _closures.closures,
          _functionClass,
        ),
        likely: _dispatch.likely(_classes.classOf),
        integers: _dispatch.created(boxElement(.integer), _classes.classOf),
        allocate: _needs.allocate,
        raise: _needs.raise,
        stackOverflow: _needs.stackOverflow,
        outOfMemory: _needs.outOfMemory,
        uncaught: _needs.uncaught,
        callback: _needs.callback,
        spawned: _needs.spawned,
        exports: exports,
        eventLoop: _needs.eventLoop,
      );

  Iterable<HirFunction> get _allFunctions => [
    ..._functions.all,
    ..._globals.getters,
    ..._fields.functions,
    ..._dispatch.made,
    ..._closures.made,
    ..._dynamics.made,
    ..._bodies,
    ..._creators.functions,
    ..._typeFunctions.functions,
    ..._links.functions,
    ..._applications.functions,
    ..._forwarders.functions,
  ];

  /// Adds what the functions found so far need of the runtime.
  void _addRuntime() {
    if (_closures.closures.isNotEmpty) _dispatch.instantiate(_functionClass);
    if (_links.schedulers.any(_functions.contains)) _needs.addEvents();
    if (_links.setExitCode case final setter?
        when _functions.contains(setter)) {
      _needs.addExitCode();
    }
    _needs.update(_allFunctions);
  }

  @override
  HirFunction runtime(String name) => functionOf(_links.function(name))!;

  @override
  Captures capturesOf(AstNode declaration) =>
      _captures[declaration] ??= Captures.of(declaration);

  @override
  HirClass cellClass(HirType type) {
    _needs.addAllocation();
    return _cells[type] ??= HirClass('cell of ${type.dartName}', null, [
      HirField('value', type),
    ]);
  }

  @override
  void addClosure(Closure closure) {
    _closures.add(closure);
    _needs.addAllocation();
  }

  @override
  void addLocalFunction(HirFunction function) => _bodies.add(function);

  @override
  void addLocalClass(HirClass class_) {
    _localClasses.add(class_);
    _needs.addAllocation();
  }

  @override
  HirSelector callSelector(int types, int positional, List<String> named) =>
      _closures.selectorOf(types, positional, named);

  /// Whether the program declares [element].
  bool _declares(ExecutableElement element) =>
      _declarations[element is ConstructorElement
          ? element.enclosingElement
          : element] !=
      null;

  late final _objects = FunctionObjects(_closures, _types, _declares);

  @override
  HirConstObject? functionObject(
    ExecutableElement element,
    FunctionType type,
  ) => _objects.of(element, type);

  @override
  HirValue? instantiate(
    FunctionBuilder builder,
    ExecutableElement element,
    List<DartType> types,
  ) {
    _needs.addAllocation();
    return _objects.instantiate(builder, element, types);
  }

  @override
  ClassElement runtimeClass(String name) => _links.heapClass(name);

  @override
  ClassElement get functionClass => _core.getClass('Function')!;

  /// The class of objects that are functions.
  ClassElement get _functionClass => _core.getClass('_Closure')!;

  @override
  void addCallbacks() => _needs.addCallbacks();

  @override
  void addSpawning() => _needs.addSpawning();

  @override
  void addNativeFinalizers() =>
      _typeFunctions.finalize ??= runtime('finalizeNative');

  @override
  late final NativeTable natives = NativeTable(this, _unit);

  @override
  late final DeferredTable deferred = DeferredTable(this, _unit);

  @override
  ClassElement get futureClass => _core.typeProvider.futureElement;

  @override
  FunctionType runtimeFunctionType(String name) => _links.functionType(name);

  @override
  ClassElement get recordClass => _core.getClass('_Record')!;

  @override
  HirValue record(
    FunctionBuilder builder,
    List<String> names,
    List<HirValue> values,
  ) => newArray(
    builder,
    createdClass(recordClass),
    builder.add(this.names(names)),
    values,
  );

  @override
  HirInstruction names(List<String> names) {
    createdClass(recordClass);
    return HirStatic(_constants.strings(names));
  }

  @override
  HirValue? typeValue(FunctionBuilder builder, DartType type) {
    _prepareTypes();
    return _types.value(builder, type);
  }

  @override
  HirConstObject? typeObject(DartType type) {
    _prepareTypes();
    final own = _types.constant(type);
    if (own == null) return null;
    final class_ = _core.getClass('_Type')!, target = createdClass(class_);
    return _constants.canonical(
      class_,
      HirConstObject(target, {target.fields.single: own}),
    );
  }

  @override
  HirValue? tearOffType(
    FunctionBuilder builder,
    ExecutableElement element, {
    FunctionType? asType,
    bool instanceMethod = false,
    Set<FormalParameterElement> unchecked = const {},
  }) {
    _prepareTypes();
    return _types.tearOffType(
      builder,
      element,
      asType: asType,
      instanceMethod: instanceMethod,
      unchecked: unchecked,
    );
  }

  @override
  HirValue? typeList(FunctionBuilder builder, List<DartType> types) {
    _prepareTypes();
    return _types.listValue(builder, types);
  }

  @override
  HirValue list(FunctionBuilder builder, DartType type, List<HirValue> values) {
    final types = typeList(builder, [type])!;
    final class_ = createdClass(_core.getClass('_List')!);
    return newArray(builder, class_, types, values);
  }

  @override
  HirField? argumentsOf(Level level) => _classes.argumentsOf(level);

  /// Makes the classes that describe types part of the program.
  void _prepareTypes() {
    for (final name in const ['BasicType', 'SuperList', 'VariableType']) {
      createdClass(runtimeClass(name));
    }
  }

  @override
  HirSelector tearOffSelector(
    ExecutableElement element,
    InterfaceElement receiver,
  ) => _dispatch.tearOffSelector(element, receiver);

  @override
  HirValue tearOff(
    FunctionBuilder builder,
    Implementation found,
    HirValue receiver, {
    bool isForwarder = false,
    InterfaceElement? class_,
  }) {
    _needs.addAllocation();
    return _closures.tearOff(
      builder,
      found,
      receiver,
      isForwarder: isForwarder,
      class_: class_,
    );
  }

  @override
  HirValue extensionTearOff(
    FunctionBuilder builder,
    MethodElement element,
    HirValue receiver,
    HirValue? types,
  ) {
    _needs.addAllocation();
    return _closures.extensionTearOff(builder, element, receiver, types);
  }

  @override
  HirSelector get applySelector => _applications.use();

  @override
  HirValue partial(
    FunctionBuilder builder,
    HirValue function,
    (HirValue, int) types,
  ) {
    _needs.addAllocation();
    return _closures.partial(builder, function, types);
  }

  @override
  HirFunction forwarderOf(Level level, ExecutableElement element) =>
      _forwarders.of(level, element);

  @override
  void translateBody(
    FunctionBuilder builder,
    FunctionBody body, [
    HirCoroutine? coroutine,
  ]) {
    StatementTranslator(this, builder).body(body);
    if (builder.finish(coroutine) case final frame?) addLocalClass(frame);
  }

  @override
  HirValue evaluate(FunctionBuilder builder, Expression node, DartType type) =>
      ExpressionTranslator(this, builder).valueTo(node, type);

  @override
  HirSelector dynamicSelector(DynamicShape shape) =>
      _dynamics.selectorOf(shape);

  @override
  HirFunction dynamicNull(HirSelector selector) =>
      _dynamics.forNull(selector, _core.getClass('Null')!);

  @override
  HirInstruction text(String value) => HirStatic(_constants.text(value));

  @override
  void schedule(void Function() work) => _pending.add(work);

  @override
  HirClass boxClass(HirType type) => createdClass(boxElement(type));

  @override
  ClassElement boxElement(HirType type) => _core.getClass(boxName(type))!;

  @override
  HirConstObject boxOf(Object value) => _constants.box(value);

  @override
  HirInstruction get trace => _links.trace;

  @override
  HirTypeTest get errorTest => _tests.extendsOf(_core.getClass('Error')!);

  @override
  HirTypeTest get unsendableTest => _tests.unsendable;

  @override
  HirTypeTest testOf(InterfaceElement class_) => _tests.testOf(class_);

  @override
  HirFunction? functionOf(ExecutableElement element) {
    final library = element.library;
    if ('${library.uri}' == 'dart:_heap/program.dart') {
      return _typeFunctions.named(element.displayName);
    }
    return _declarations[element] == null ? null : _functions.of(element);
  }

  @override
  String? operationOf(ExecutableElement element) =>
      RuntimeLinks.operationOf(element);

  @override
  bool declares(InstanceElement class_) =>
      _declarations[class_.baseElement] != null;

  @override
  HirClass classAt(Level level) => _classes.atLevel(level);

  @override
  GlobalVariable? globalOf(PropertyInducingElement element) =>
      _globals.of(element);

  @override
  HirInstruction? constantOf(HirType? type, DartObject? object) =>
      _constants.of(type, object)?.instruction;

  @override
  HirInstruction defaultOf(FormalParameterElement parameter) =>
      _constants.defaultOf(parameter);

  @override
  HirFunction memberOf(Level level, ExecutableElement element) =>
      _functions.of(element, level);

  @override
  HirFunction? functionAt(
    Level level,
    ExecutableElement member,
    int positional,
    List<String> named,
    Reject reject, {
    bool isUnboxed = false,
    bool orForwarder = false,
  }) => _dispatch.functionAt(
    level,
    member,
    positional,
    named,
    reject,
    isUnboxed: isUnboxed,
    orForwarder: orForwarder,
  );

  @override
  Level levelOf(InterfaceElement class_) => _classes.levels.of(class_);

  @override
  HirFunction initializerOf(ConstructorElement element) =>
      _functions.of(element);

  @override
  HirFunction factoryOf(ConstructorElement element) {
    final name = RuntimeLinks.environmentFunction(element);
    return name == null ? _functions.of(element) : runtime(name);
  }

  @override
  HirClass createdClass(InterfaceElement element) {
    final class_ = _classes.classOf(element);
    _dispatch.instantiate(element);
    _needs.addAllocation();
    return class_;
  }

  @override
  FieldPlace fieldOf(Level level, FieldElement element) =>
      _classes.fieldOf(level, element);

  @override
  HirValue loadField(
    FunctionBuilder builder,
    Level level,
    FieldElement element,
    HirValue object,
  ) => _fields.load(builder, level, element, object);

  @override
  void storeField(
    FunctionBuilder builder,
    Level level,
    FieldElement element,
    HirValue object,
    HirValue value,
  ) => _fields.store(builder, level, element, object, value);

  @override
  HirSelector selectorOf(
    ExecutableElement member,
    InterfaceElement receiver,
    int positional,
    List<String> named,
    Reject reject, {
    required bool isOwn,
  }) => _dispatch.selectorOf(
    member,
    receiver,
    positional,
    named,
    reject,
    isOwn: isOwn,
  );
}
