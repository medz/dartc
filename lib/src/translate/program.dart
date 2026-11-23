import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';
import 'package:dartc/source.dart';

import 'builder.dart';
import 'builtin_error.dart';
import 'captures.dart';
import 'classes.dart';
import 'closure.dart';
import 'closure_table.dart';
import 'constant_table.dart';
import 'constructor.dart';
import 'dispatch.dart';
import 'dynamic_shape.dart';
import 'dynamic_table.dart';
import 'error_table.dart';
import 'global_table.dart';
import 'members.dart';
import 'report.dart';
import 'scope.dart';
import 'statement.dart';
import 'type_functions.dart';
import 'type_table.dart';
import 'types.dart';

/// Translates everything the program's `main` can reach.
///
/// Throws [CompileFailure] at the first construct not supported yet.
///
/// A program that needs it includes the [runtime], if given.
HirModule translateProgram(SourceProgram program, {SourceProgram? runtime}) =>
    ProgramTranslator(program, runtime).translate();

/// Finds the functions a program needs and translates each once.
///
/// Functions, classes and selectors only grow and are bounded by the source.
final class ProgramTranslator(
  final SourceProgram program,
  final SourceProgram? _runtime,
) implements ProgramScope {
  SourceUnit get _unit => program.main.units.first;
  LibraryElement get _core =>
      program.main.element.typeProvider.objectElement.library;
  late final _declarations = Declarations([
    ...program.libraries,
    ...?_runtime?.libraries,
  ]);
  late final _classes = ClassTable(_declarations);
  late final _dispatch = DispatchBuilder(this, _declarations, _unit);
  late final ConstantTable _constants = ConstantTable(
    _declarations,
    _classes,
    _core,
    _functionConstant,
    (types) => _types.list(types),
    _dispatch.instantiate,
  );
  late final TypeTable _types = TypeTable(this, _classes, _constants);
  late final _typeFunctions = TypeFunctions(this, _unit, _classes, _types);
  late final _closures = ClosureTable(this, _unit, _creatorOf);
  late final _dynamics = DynamicTable(this, _unit);
  late final _errors = ErrorTable(_classes, _core, _dispatch.instantiate);
  late final _globals = GlobalTable(
    this,
    _declarations,
    _constants,
    _pending.add,
  );
  final _functions = <ExecutableElement, HirFunction>{};
  final _pending = <void Function()>[];
  final _captures = <AstNode, Captures>{};
  final _cells = <HirType, HirClass>{};

  /// The functions of closures.
  final _bodies = <HirFunction>[];
  final _creators = <ConstructorElement, HirFunction>{};
  final _locals = <Element, HirFunction>{};

  /// The classes of local functions that are no values.
  final _localClasses = <HirClass>[];
  final _thrown = <ClassElement>{};
  HirFunction? _allocate, _raise, _outOfMemory, _stackOverflow, _writeNumber;

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
    final main = HirFunction(entry.displayName, const []);
    _functions[entry] = main;
    _pending.add(() => _translate(entry));
    do {
      while (_pending.isNotEmpty) {
        _pending.removeLast()();
      }
      _addRuntime();
    } while (_dispatch.update() ||
        _closures.update() ||
        _dynamics.update(
          _dispatch.classes.where((class_) => !_isRuntime(class_.library)),
          _classes.classOf,
          _closures.closures,
        ) ||
        _typeFunctions.update(_dispatch.classes, _closures.closures) ||
        _pending.isNotEmpty);
    _typeFunctions.finish();
    final dispatch = {
      ..._dispatch.result(_classes.classOf, _closures),
      ..._closures.dispatch,
      ..._dynamics.dispatch,
      if (_typeFunctions.isUsed) _typeFunctions.typeOf: _typeFunctions.entries,
    };
    final report = ReportBuilder(
      _declarations,
      _classes,
      _errors,
      _thrown,
      _writeNumber,
      runtime,
    );
    final uncaught = _canThrow ? report.build(_dispatch.classes) : null;
    return HirModule(
      main,
      [..._allFunctions, ?uncaught],
      classes: [
        ..._dispatch.classes.map(_classes.classOf),
        for (final closure in _closures.closures) closure.class_,
        ..._localClasses,
        ..._cells.values,
      ],
      dispatch: dispatch,
      globals: _globals.globals,
      tests: {
        ..._errors.results(_dispatch.classes),
        ..._closures.tests,
        ..._closures.exact,
        ...report.tests,
      },
      allocate: _allocate,
      raise: _raise,
      stackOverflow: _stackOverflow,
      outOfMemory: _outOfMemory,
      uncaught: uncaught,
    );
  }

  Iterable<HirFunction> get _allFunctions => [
    ..._functions.values,
    ..._globals.getters,
    ..._dispatch.made,
    ..._closures.made,
    ..._dynamics.made,
    ..._bodies,
    ..._creators.values,
    ..._typeFunctions.functions,
    ..._errors.functions,
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
    if (!_canThrow) return;
    _stackOverflow ??= _errors.throwerOf(.stackOverflow);
    _raise ??= _runtimeFunction('raise');
    if (_allocate != null) _outOfMemory ??= _errors.throwerOf(.outOfMemory);
    final int = _core.getClass('int')!;
    final throwsInts =
        _dispatch.classes.contains(int) &&
        _thrown.any((class_) => isSubclass(int, class_));
    final throwsGenerics = _dispatch.classes.any(
      (class_) =>
          class_.typeParameters.isNotEmpty &&
          _thrown.any((thrown) => isSubclass(class_, thrown)),
    );
    if (throwsGenerics) runtime('writeObjectType');
    if (throwsInts || _errors.throwerIfMade(.negativeShift) != null) {
      _writeNumber ??= _runtimeFunction('writeNumber');
    }
  }

  /// The function called [name] in the runtime, if there is one.
  HirFunction? _runtimeFunction(String name) {
    for (final library in _runtime?.libraries ?? const <SourceLibrary>[]) {
      final found = library.element.getTopLevelFunction(name);
      if (found != null) return _declare(found);
    }
    return null;
  }

  bool _isRuntime(LibraryElement library) =>
      _runtime?.libraries.any((own) => own.element == library) ?? false;

  @override
  HirFunction throwerOf(BuiltinError error) {
    final thrower = _errors.throwerOf(error);
    if (!error.isExhaustion) _addAllocation();
    return thrower;
  }

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
  void addClosure(
    Closure closure,
    HirFunction function, {
    required bool isValue,
  }) {
    _bodies.add(function);
    isValue ? _closures.add(closure) : _localClasses.add(closure.class_);
    _addAllocation();
  }

  @override
  HirFunction localFunction(Element element) => _locals[element]!;

  @override
  void setLocalFunction(Element element, HirFunction function) =>
      _locals[element] = function;

  @override
  HirSelector callSelector(int positional, List<String> named) =>
      _closures.selectorOf(positional, named);

  @override
  HirTypeTest get functionTest => _closures.anyFunction;

  /// Whether the program declares [element].
  bool _declares(ExecutableElement element) =>
      _declarations[element is ConstructorElement
          ? element.enclosingElement
          : element] !=
      null;

  @override
  HirConstObject? functionObject(ExecutableElement element) =>
      _declares(element) ? _closures.constant(element, null) : null;

  /// The function [element] as a constant of [type].
  HirConstObject? _functionConstant(ExecutableElement element, DartType type) {
    if (!_declares(element) || type is! FunctionType) return null;
    if (takesTypes(element) == null) return functionObject(element);
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
  InterfaceElement canonicalClass(InterfaceElement class_) {
    final base = class_.baseElement as InterfaceElement;
    return base.library.isDartCore ? _core.getClass(base.name!) ?? base : base;
  }

  @override
  ClassElement runtimeClass(String name) {
    for (final library in _runtime?.libraries ?? const <SourceLibrary>[]) {
      final found = library.element.getClass(name);
      if (found != null) return found;
    }
    throw StateError('No runtime with $name.');
  }

  @override
  ClassElement get functionClass => _core.getClass('Function')!;

  @override
  HirValue? typeValue(FunctionBuilder builder, DartType type) {
    _prepareTypes();
    return _types.value(builder, type);
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
  Constant? constantTypes(List<DartType> types) => _types.list(types);

  @override
  HirField? argumentsOf(ClassElement class_) => _classes.argumentsOf(class_);

  /// Makes the classes that describe types part of the program.
  void _prepareTypes() {
    if (_runtime == null) return;
    for (final name in const ['BasicType', 'SuperList', 'VariableType']) {
      createdClass(runtimeClass(name));
    }
  }

  @override
  HirSelector tearOffSelector(
    ExecutableElement element,
    ClassElement receiver,
  ) => _dispatch.tearOffSelector(element, receiver);

  @override
  HirValue tearOff(
    FunctionBuilder builder,
    ExecutableElement element,
    HirValue receiver,
  ) {
    _addAllocation();
    return _closures.tearOff(builder, element, receiver);
  }

  @override
  void translateBody(FunctionBuilder builder, FunctionBody body) {
    StatementTranslator(this, builder).body(body);
    builder.finish();
  }

  @override
  HirSelector dynamicSelector(DynamicShape shape) =>
      _dynamics.selectorOf(shape);

  @override
  int missingNumber(String kind, String name) {
    runtime('writeObjectType');
    return _errors.missingNumber(kind, name);
  }

  @override
  void schedule(void Function() work) => _pending.add(work);

  /// A function that creates an object and initializes it.
  HirFunction _creatorOf(ConstructorElement element) {
    if (element.isFactory) return factoryOf(element);
    return _creators[element] ??= () {
      final initializer = initializerOf(element);
      final class_ = element.enclosingElement as ClassElement;
      final function = HirFunction(
        'create ${initializer.name}',
        initializer.parameters.skip(1),
        .reference,
      );
      final builder = FunctionBuilder(_unit, function, const []);
      final object = builder.create(createdClass(class_));
      builder
        ..call(HirCall(initializer, [object, ...builder.inputs]))
        ..end(HirReturn(object))
        ..finish();
      return function;
    }();
  }

  @override
  HirClass boxClass(HirType type) => createdClass(
    _core.getClass(type.dartName) ?? (throw StateError('No box of $type.')),
  );

  @override
  HirConstObject boxOf(Object value) => _constants.box(value);

  @override
  int castNumber(String? type, String ending) {
    runtime('writeObjectType');
    if (type == null) runtime('writeType');
    return _errors.castNumber(type, ending);
  }

  @override
  HirFunction runtime(String name) =>
      _runtimeFunction(name) ?? (throw StateError('No runtime with $name.'));

  @override
  int lateNumber(String name) => _errors.lateNumber(name);

  @override
  HirClass get traceClass {
    _addAllocation();
    return _errors.trace;
  }

  @override
  void addThrown(ClassElement class_) => _thrown.add(class_);

  @override
  HirTypeTest testOf(ClassElement class_) => _errors.testOf(class_);

  @override
  HirFunction? functionOf(ExecutableElement element) {
    final library = element.library;
    if (_isRuntime(library) && library.uri.path.endsWith('/program.dart')) {
      return _typeFunctions.named(element.displayName);
    }
    return _declarations[element] == null ? null : _declare(element);
  }

  @override
  HirMachineOp? machineOpOf(ExecutableElement element) {
    final library = element.library;
    return _isRuntime(library) && library.uri.path.endsWith('/machine.dart')
        ? HirMachineOp.values.byName(element.displayName)
        : null;
  }

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
  HirFunction memberOf(ExecutableElement element) => _declare(element);

  @override
  HirFunction initializerOf(ConstructorElement element) => _declare(element);

  @override
  HirFunction factoryOf(ConstructorElement element) {
    if (element.redirectedConstructor != null) {
      throw _declarations.unsupported(element, 'redirecting factories');
    }
    return _declare(element);
  }

  @override
  HirClass createdClass(ClassElement element) {
    final class_ = _classes.classOf(element);
    _dispatch.instantiate(element);
    _addAllocation();
    return class_;
  }

  void _addAllocation() => _allocate ??= _runtimeFunction('allocate');

  @override
  HirField fieldOf(FieldElement element) => _classes.fieldOf(element);

  @override
  HirSelector selectorOf(
    ExecutableElement member,
    ClassElement receiver,
    int positional,
    List<String> named,
    Reject reject,
  ) => _dispatch.selectorOf(member, receiver, positional, named, reject);

  HirFunction _declare(ExecutableElement element) =>
      _functions.putIfAbsent(element, () {
        _pending.add(() => _translate(element));
        final owner = element.enclosingElement;
        final result = element.returnType;
        final isInitializer = isInitializerElement(element);
        return HirFunction(
          owner is InstanceElement
              ? '${owner.displayName}.${element.lookupName}'
              : element.displayName,
          [
            if (hasReceiver(element)) .reference,
            if (takesTypes(element) != null) .reference,
            for (final parameter in element.formalParameters)
              valueType(parameter.type) ??
                  (throw _declarations.unsupported(
                    element,
                    'a parameter of type ${parameter.type}',
                  )),
          ],
          isInitializer || hasNoResult(result)
              ? null
              : valueType(result) ??
                    (throw _declarations.unsupported(
                      element,
                      'a result of type $result',
                    )),
          !_isRuntime(element.library),
        );
      });

  void _translate(ExecutableElement element) {
    final declared = _declarations[element];
    final owner = element.enclosingElement;
    final (unit, node) = declared ?? _declarations[owner as ClassElement]!;
    final builder = FunctionBuilder(
      unit,
      _functions[element]!,
      element.formalParameters,
      receiverClass: hasReceiver(element) ? owner as ClassElement : null,
      returnType: element.returnType,
      typeOwner: takesTypes(element),
      captures: capturesOf(declarationOf(node)),
      cellClass: cellClass,
    );
    final statements = StatementTranslator(this, builder);
    if (isInitializerElement(element)) {
      ConstructorTranslator(
        this,
        _declarations,
        builder,
        statements,
      ).initializer(element as ConstructorElement);
    } else {
      final body = switch (node) {
        FunctionDeclaration(
          functionExpression: FunctionExpression(:final body),
        ) ||
        MethodDeclaration(:final body) ||
        ConstructorDeclaration(:final body) => body,
        _ => throw StateError('Unexpected declaration $node.'),
      };
      if (body.isAsynchronous || body.isGenerator) {
        throw unit.unsupported(body, 'async and generator functions');
      }
      statements.body(body);
    }
    builder.finish();
  }
}
