import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';
import 'package:dartc/source.dart';

import 'apply_table.dart';
import 'builder.dart';
import 'captures.dart';
import 'classes.dart';
import 'closure.dart';
import 'closure_table.dart';
import 'constant_table.dart';
import 'creators.dart';
import 'dispatch.dart';
import 'dynamic_shape.dart';
import 'dynamic_table.dart';
import 'expression.dart';
import 'field_table.dart';
import 'forwarders.dart';
import 'function_table.dart';
import 'global_table.dart';
import 'levels.dart';
import 'members.dart';
import 'runtime_links.dart';
import 'scope.dart';
import 'statement.dart';
import 'test_table.dart';
import 'type_functions.dart';
import 'type_table.dart';
import 'types.dart';

/// Translates everything the program's `main` can reach.
///
/// Throws [CompileFailure] at the first construct not supported yet.
///
HirModule translateProgram(SourceProgram program) =>
    ProgramTranslator(program).translate();

/// Finds the functions a program needs and translates each once.
///
/// Functions, classes and selectors only grow and are bounded by the source.
final class ProgramTranslator(final SourceProgram program)
    implements ProgramScope {
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
    _functionConstant,
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
  HirFunction? _allocate, _raise, _outOfMemory, _stackOverflow, _uncaught;

  HirModule translate() {
    final start = program.main.units.first;
    final entry = program.main.element.entryPoint;
    if (entry == null) {
      throw CompileFailure([
        start.problemAt(0, 'The program has no main function.'),
      ]);
    }
    if (entry.formalParameters.isNotEmpty) {
      throw _declarations.unsupported(entry, 'parameters of main');
    }
    final main = _functions.main(entry);
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
    final dispatch = {
      ..._dispatch.result(_classes.classOf, _closures, _functionClass),
      ..._closures.dispatch,
      ..._dynamics.dispatch,
      ..._typeFunctions.dispatch,
      ..._applications.dispatch,
    };
    return HirModule(
      main,
      _allFunctions,
      classes: [
        ..._dispatch.classes.map(_classes.classOf),
        for (final closure in _closures.closures) closure.class_,
        ..._localClasses,
        ..._cells.values,
      ],
      dispatch: dispatch,
      globals: _globals.globals,
      tests: _tests.results(
        _dispatch.classes,
        _closures.closures,
        _functionClass,
      ),
      allocate: _allocate,
      raise: _raise,
      stackOverflow: _stackOverflow,
      outOfMemory: _outOfMemory,
      uncaught: _uncaught,
    );
  }

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

  /// Whether the program throws, or calls what may use up the stack.
  bool get _canThrow => _allFunctions.any(
    (function) => function.blocks.any(
      (block) =>
          block.terminator is HirInvoke ||
          block.terminator is HirThrow ||
          block.instructions.any((instruction) => instruction is HirCalling),
    ),
  );

  /// Adds what the functions found so far need of the runtime.
  void _addRuntime() {
    if (_closures.closures.isNotEmpty) _dispatch.instantiate(_functionClass);
    if (!_canThrow) return;
    _stackOverflow ??= _links.exhaustion('StackOverflowError');
    _raise ??= runtime('raise');
    _uncaught ??= runtime('reportUncaught');
    if (_allocate == null) return;
    _outOfMemory ??= _links.exhaustion('OutOfMemoryError');
  }

  @override
  HirFunction runtime(String name) => _functions.of(_links.function(name));

  @override
  Captures capturesOf(AstNode declaration) =>
      _captures[declaration] ??= Captures.of(declaration);

  @override
  HirClass cellClass(HirType type) {
    _addAllocation();
    return _cells[type] ??= HirClass('cell of ${type.dartName}', null, [
      HirField('value', type),
    ]);
  }

  @override
  void addClosure(Closure closure) {
    _closures.add(closure);
    _addAllocation();
  }

  @override
  void addLocalFunction(HirFunction function) => _bodies.add(function);

  @override
  void addLocalClass(HirClass class_) {
    _localClasses.add(class_);
    _addAllocation();
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

  @override
  HirConstObject? functionObject(ExecutableElement element) =>
      !_declares(element)
      ? null
      : element.typeParameters.isEmpty
      ? _closures.constant(element, null)
      : _closures.generic(element);

  /// The function [element] as a constant of [type].
  HirConstObject? _functionConstant(ExecutableElement element, DartType type) {
    if (!_declares(element) || type is! FunctionType) return null;
    if (takesTypes(element) == null || type.typeParameters.isNotEmpty) {
      return functionObject(element);
    }
    final types = _types.list(typeArgumentsOf(element, type));
    return types == null
        ? null
        : _closures.constant(element, types.value as HirConstObject?);
  }

  @override
  HirValue? instantiate(
    FunctionBuilder builder,
    ExecutableElement element,
    List<DartType> types,
  ) {
    if (!_declares(element)) return null;
    if (_types.list(types) case final found?) {
      return builder.add(
        HirStatic(_closures.constant(element, found.value as HirConstObject?)),
      );
    }
    final list = _types.listValue(builder, types);
    if (list == null) return null;
    _addAllocation();
    final class_ = _closures.static(element).class_;
    final object = builder.create(class_);
    builder.add(HirStore(class_.fields.single, object, list));
    return object;
  }

  @override
  ClassElement runtimeClass(String name) => _links.heapClass(name);

  @override
  ClassElement get functionClass => _core.getClass('Function')!;

  /// The class of objects that are functions.
  ClassElement get _functionClass => _core.getClass('_Closure')!;

  @override
  ClassElement get recordClass => _core.getClass('_Record')!;

  @override
  HirValue record(
    FunctionBuilder builder,
    List<String> names,
    List<HirValue> values,
  ) => _array(builder, recordClass, builder.add(this.names(names)), values);

  @override
  HirInstruction names(List<String> names) {
    final record = createdClass(recordClass);
    assert(record.elements != null);
    return HirStatic(_constants.names(names));
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
  HirValue? methodType(FunctionBuilder builder, ExecutableElement element) {
    _prepareTypes();
    return _types.methodType(builder, element);
  }

  @override
  HirValue? typeList(FunctionBuilder builder, List<DartType> types) {
    _prepareTypes();
    return _types.listValue(builder, types);
  }

  @override
  HirValue list(FunctionBuilder builder, DartType type, List<HirValue> values) {
    final types = typeList(builder, [type])!;
    return _array(builder, _core.getClass('_List')!, types, values);
  }

  /// An array of [element] that holds [values], and [own] in its field.
  HirValue _array(
    FunctionBuilder builder,
    ClassElement element,
    HirValue own,
    List<HirValue> values,
  ) {
    final class_ = createdClass(element);
    final length = builder.add(HirConst(values.length));
    final array = builder.call(HirNewArray(class_, length))!;
    builder.add(HirStore(class_.fields.single, array, own));
    for (final (i, value) in values.indexed) {
      final index = builder.add(HirConst(i));
      builder.add(HirStoreElement(.reference, array, index, value));
    }
    return array;
  }

  @override
  Constant? constantTypes(List<DartType> types) => _types.list(types);

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
  }) {
    _addAllocation();
    return _closures.tearOff(
      builder,
      found,
      receiver,
      isForwarder: isForwarder,
    );
  }

  @override
  HirValue extensionTearOff(
    FunctionBuilder builder,
    MethodElement element,
    HirValue receiver,
    HirValue? types,
  ) {
    _addAllocation();
    return _closures.extensionTearOff(builder, element, receiver, types);
  }

  @override
  HirSelector get applySelector => _applications.use();

  @override
  HirValue partial(
    FunctionBuilder builder,
    HirValue function,
    (HirValue, int) types,
    FunctionType type,
  ) {
    _addAllocation();
    return _closures.partial(builder, function, types, type);
  }

  @override
  HirFunction forwarderOf(Level level, ExecutableElement element) =>
      _forwarders.of(level, element);

  @override
  void translateBody(FunctionBuilder builder, FunctionBody body) {
    StatementTranslator(this, builder).body(body);
    builder.finish();
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
  ClassElement boxElement(HirType type) => _core.getClass(switch (type) {
    .integer => '_Mint',
    .float => '_Double',
    _ => 'bool',
  })!;

  @override
  HirConstObject boxOf(Object value) => _constants.box(value);

  @override
  HirInstruction get trace => _links.trace;

  @override
  HirTypeTest get errorTest => _tests.extendsOf(_core.getClass('Error')!);

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
  String? pragmaOf(Element element, String name) =>
      _declarations.pragmaOf(element, name);

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
  }) => _dispatch.functionAt(
    level,
    member,
    positional,
    named,
    reject,
    isUnboxed: isUnboxed,
  );

  @override
  Level levelOf(InterfaceElement class_) => _classes.levels.of(class_);

  @override
  HirFunction initializerOf(ConstructorElement element) =>
      _functions.of(element);

  @override
  HirFunction factoryOf(ConstructorElement element) => _functions.of(element);

  @override
  HirClass createdClass(InterfaceElement element) {
    final class_ = _classes.classOf(element);
    _dispatch.instantiate(element);
    _addAllocation();
    return class_;
  }

  void _addAllocation() => _allocate ??= runtime('allocate');

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
    Reject reject,
  ) => _dispatch.selectorOf(member, receiver, positional, named, reject);
}
