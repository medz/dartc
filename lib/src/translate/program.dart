import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/hir.dart';
import 'package:dartc/source.dart';

import 'builder.dart';
import 'builtin_error.dart';
import 'classes.dart';
import 'constant_table.dart';
import 'constructor.dart';
import 'dispatch.dart';
import 'error_table.dart';
import 'global_table.dart';
import 'report.dart';
import 'scope.dart';
import 'statement.dart';
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
  late final _constants = ConstantTable(
    _declarations,
    _classes,
    _core,
    _dispatch.instantiate,
  );
  late final _errors = ErrorTable(_classes, _core, _dispatch.instantiate);
  late final _globals = GlobalTable(
    this,
    _declarations,
    _constants,
    _pending.add,
  );
  final _functions = <ExecutableElement, HirFunction>{};
  final _pending = <void Function()>[];
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
    } while (_dispatch.update() || _pending.isNotEmpty);
    final report = ReportBuilder(
      _declarations,
      _classes,
      _errors,
      _thrown,
      _writeNumber,
    );
    final uncaught = _canThrow ? report.build(_dispatch.classes) : null;
    return HirModule(
      main,
      [..._allFunctions, ?uncaught, ?report.describe],
      classes: _dispatch.classes.map(_classes.classOf),
      dispatch: _dispatch.result(_classes.classOf),
      globals: _globals.globals,
      tests: {..._errors.results(_dispatch.classes), ...report.tests},
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
  HirClass boxClass(HirType type) => createdClass(
    _core.getClass(type.dartName) ?? (throw StateError('No box of $type.')),
  );

  @override
  HirConstObject boxOf(Object value) => _constants.box(value);

  @override
  int castNumber(String text) => _errors.castNumber(text);

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
  HirFunction? functionOf(ExecutableElement element) =>
      _declarations[element] == null ? null : _declare(element);

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
      final (parameters, body) = switch (node) {
        FunctionDeclaration(
          functionExpression: FunctionExpression(
            :final typeParameters,
            :final body,
          ),
        ) ||
        MethodDeclaration(
          :final typeParameters,
          :final body,
        ) => (typeParameters, body),
        ConstructorDeclaration(:final body) => (null, body),
        _ => throw StateError('Unexpected declaration $node.'),
      };
      if (parameters != null) {
        throw unit.unsupported(parameters, 'type parameters');
      }
      if (body.isAsynchronous || body.isGenerator) {
        throw unit.unsupported(body, 'async and generator functions');
      }
      statements.body(body);
    }
    builder.finish();
  }
}
