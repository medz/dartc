import 'package:dartc/abi.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/target.dart';

import 'native_boundaries.dart';
import 'program_selection.dart';
import 'program_layout.dart';
import 'heap_plan.dart';
import 'heap_runtime.dart';
import 'checked_casts.dart';
import 'member_calls.dart';
import 'instance_storage.dart';
import 'closure_storage.dart';
import 'string_storage.dart';
import 'record_storage.dart';
import 'type_environment.dart';
import 'type_implementations.dart';
import 'callable_implementations.dart';
import 'native_views.dart';

/// Prepares a closed source graph after execution lowerings and analysis.
///
/// Runtime definitions and actual generated calls must already be in [program].
/// Missing execution edges fail here; preparation never widens unknown roots.
final class ProgramPreparation(
  /// The output platform used for layouts and native bindings.
  final Target target,

  /// The graph after semantic and boundary normalization and any rewrites.
  final IrProgram program, {
  required NativeBoundaries boundaries,
  Map<FunctionTarget, NativeImport> imports = const {},
  Map<NativeReference, String> nativeSymbols = const {},
  ({FunctionTarget function, String symbol})? entryPoint,
  HeapRuntime? runtime,
  TypeImplementations? typeImplementations,
  CallableImplementations? callableImplementations,
  NativeViews? nativeViews,
}) {
  /// Independently callable source, export and process entries.
  late final Set<FunctionTarget> roots;

  /// Metadata classes materialized by generated code.
  Iterable<ClassType> get instantiatedTypes => TypeMetadata.fields.keys;

  final _nativeSymbols = Map<NativeReference, String>.unmodifiable(
    nativeSymbols,
  );
  final _entryPoint = entryPoint;
  final _runtime = runtime?.rebind(program);
  late final TypeImplementations _typeImplementations;
  late final CallableImplementations _callableImplementations;
  final _nativeViews = nativeViews;
  final NativeBoundaries _boundaries = boundaries;
  late final Map<FunctionTarget, NativeImport> _imports;

  this {
    _typeImplementations =
        typeImplementations ?? TypeImplementations(runtime: _runtime?.types);
    _typeImplementations.rebind(_runtime?.types);
    _callableImplementations =
        callableImplementations ??
        CallableImplementations(types: _typeImplementations);
    roots = .unmodifiable({...boundaries.roots});
    for (final entry in roots) {
      if (program.implementationOf(entry) == null) {
        throw ArgumentError('Missing native entry body: ${entry.name}');
      }
    }
    _imports = .unmodifiable({
      for (final MapEntry(key: raw, value: binding)
          in boundaries.imports.entries)
        raw: ?imports[binding.source],
    });
    for (final entry in _imports.entries) {
      if (entry.value.signature != boundaries.imports[entry.key]!.signature) {
        throw ArgumentError(
          'Native import signature changed after boundary lowering.',
        );
      }
      if (entry.value.isLeaf != boundaries.imports[entry.key]!.isLeaf ||
          entry.value.isNonAllocating != boundaries.imports[entry.key]!.isNonAllocating) {
        throw ArgumentError(
          'Native effect promises changed after boundary lowering.',
        );
      }
    }
    if (imports.keys.any(
      (source) =>
          !boundaries.imports.values.any((binding) => binding.source == source),
    )) {
      throw ArgumentError('Native import has no lowered boundary.');
    }
    if (entryPoint != null && !roots.contains(entryPoint.function)) {
      throw ArgumentError('Process entry must be a declared boundary root.');
    }
    if (entryPoint case (:final function, :final symbol)) {
      final body = program.implementationOf(function);
      if (symbol.isEmpty || symbol.contains('\u0000')) {
        throw ArgumentError.value(symbol, 'entryPoint.symbol');
      }
      if (body is! IrFunction ||
          body.bodyKind != .synchronous ||
          function.kind != .function ||
          (function.parameterTypes.isNotEmpty &&
              function.signature !=
                  FunctionType(function.returnType, [.integer, .integer])) ||
          function.typeParameters.isNotEmpty) {
        throw UnsupportedError(
          'Process entry requires no parameters or integer argc/argv parameters.',
        );
      }
    }
  }

  /// Prepares one dependency-closed step using facts for [program].
  ///
  /// Facts for another graph, or facts invalidated by analysis changes, fail.
  /// A rewrite requires a new preparation and a new analysis from its roots.
  PreparedProgram prepare(ProgramCallFacts facts) {
    facts.checkProgram(program);
    if (facts is ProgramFlowFacts && facts.pendingExecutionCalls.isNotEmpty) {
      throw StateError(
        'Execution entries remain unimplemented for actual source calls: '
        '${facts.pendingExecutionCalls.values.expand((targets) => targets).map((target) => target.name).toSet().join(', ')}.',
      );
    }
    if (roots.any((root) => !facts.coversEntry(root))) {
      throw ArgumentError('Call facts must cover every preparation root.');
    }
    final environment = TypeEnvironment(
      program.functions.map((function) => function.target),
    );
    while (true) {
      final revision = environment.revision;
      final result = _prepare(facts, environment);
      if (environment.revision == revision) return result;
      // A changed ABI invalidates every caller, layout and root allocation.
      // Rebuild from the same checked source before consuming dependencies.
    }
  }

  PreparedProgram _prepare(
    ProgramCallFacts facts,
    TypeEnvironment environment,
  ) {
    final program = this.program;
    final runtime = _runtime;
    final imports = _imports;
    final callbacks = _boundaries.callbacks;
    final callbackGetters = {
      for (final entry in callbacks.entries) entry.value.address: entry.key,
    };
    final sourceDefinitions = facts.definitions;
    if (program.executionShapes case final shapes?) {
      for (final function in program.functions) {
        if (facts.definitions.contains(function.target)) shapes.verify(function);
      }
    }
    final selected = sourceDefinitions.toSet();
    final heap = HeapPlan(
      runtime: runtime,
      managedContext: _boundaries.runtimeContext,
    );
    final casts = CheckedCasts(failure: runtime?.typeCheckFailure);
    IrCallable? constructor(ValueType? type, [String name = 'new']) {
      final target = program.classes
          .where((c) => c.type == type)
          .firstOrNull
          ?.constructors[name];
      return target == null ? null : program.implementationOf(target);
    }

    final lateErrorType = program.classes
        .where(
          (declaration) =>
              declaration.type.library == Uri.parse('dart:_internal') &&
              declaration.type.name == 'LateError',
        )
        .firstOrNull
        ?.type;
    final sourceBodies = sourceDefinitions
        .map(program.implementationOf)
        .whereType<IrCallable>()
        .toList();
    final bodies = sourceBodies.whereType<IrFunction>().toList();
    if (bodies.any(
      (body) => body.blocks.any(
        (block) =>
            block.instructions.any((operation) => operation is NativeCall) ||
            switch (block.end) {
              Invoke(operation: NativeCall()) => true,
              _ => false,
            },
      ),
    )) {
      throw StateError(
        'NativeCallLowering must enter analysis before preparation.',
      );
    }
    final strings = StringStorage(
      source: program.classes
          .where((c) => c.type == ValueType.string)
          .firstOrNull,
    );
    final instantiatedTypes = TypeMetadata.fields.keys;
    final records = RecordStorage(
      program.classes,
      bodies.expand((body) => body.recordTypes),
    );
    final instances = InstanceStorage(
      bodies,
      lateError: lateErrorType == null ? null : constructor(lateErrorType),
    );
    final helpers = [...instances.functions];
    final requiredTypes = {
      ...instantiatedTypes,
      for (final function in helpers) ...function.instantiatedClasses,
    };
    final members = MemberCalls(
      program,
      sourceDefinitions,
      records: records,
      instantiatedTypes: requiredTypes,
      callTypes: facts,
    );
    final functions = [...bodies, ...helpers];
    final closures = ClosureStorage(
      [...sourceBodies, ...helpers],
      storageDeclarations: program.classes,
      definitions: [...program.functions, ...program.externals],
      storedFunctions: _typeImplementations.values.descriptorFunctions,
      callableImplementations: _callableImplementations,
      boundMethods: members.tearOffTargets,
    );
    final layouts = ProgramLayout(
      [...program.classes, ...closures.classes],
      executionShapes: program.executionShapes,
      nativeLayout: NativeLayout(target),
      functions: functions,
      instanceStorage: instances,
      closureStorage: closures,
      stringStorage: strings,
      recordStorage: records,
      typeRuntime: runtime?.types,
      typeImplementations: _typeImplementations,
      typeEnvironment: environment,
      nativeViews: _nativeViews,
      referencedClasses: [
        ...instantiatedTypes,
        for (final declaration in [...closures.classes, ?records.declaration])
          declaration.type,
        for (final function in [...sourceBodies, ...helpers])
          ...function.referencedClasses,
      ],
    );
    final selection = ProgramSelection(
      layouts,
      heap,
      casts,
      members,
      instances,
      imports: imports,
      callbacks: {
        for (final entry in callbacks.entries) entry.key: entry.value.address,
      },
    );
    for (final declaration in sourceDefinitions) {
      final function = program.implementationOf(declaration);
      final binding = imports[declaration];
      if (binding != null ||
          callbackGetters.containsKey(declaration) ||
          heap.primitives.contains(declaration)) {
        continue;
      }
      if (function is IrFunction) {
        selection.include(function);
      } else {
        throw ArgumentError(
          'Definition has no body: ${declaration.library}::'
          '${declaration.owner == null ? '' : '${declaration.owner!.dartName}.'}'
          '${declaration.name}',
        );
      }
    }
    final calls = {
      for (final body in selection.functions.values) ...body.callees,
    };
    final activeCallbacks = {
      for (final entry in callbacks.entries)
        if (calls.contains(entry.value.address)) entry.key: entry.value,
    };
    final persistent = _boundaries.persistent;
    final missing = selection.close(persistent: persistent, roots: roots);
    for (final target in missing) {
      if (program.implementationOf(target) == null) {
        throw ArgumentError('Missing support dependency: ${target.name}');
      }
    }
    if (missing.isNotEmpty || selection.implicitCalls.isNotEmpty) {
      throw StateError(
        'Execution implementations must enter their actual callers before '
        'target preparation: '
        'missing definitions: ${missing.map((target) => target.name).join(', ')}; '
        'unobserved calls: ${selection.unobservedCalls.entries.map((entry) => '${entry.value.caller.owner?.name ?? ''}.${entry.value.caller.name} '
            '[${entry.key.runtimeType}] -> '
            '${entry.value.target.owner?.name ?? ''}.${entry.value.target.name}').join(', ')}',
      );
    }
    final nativeEntries = {
      ..._boundaries.exports.keys,
      for (final callback in activeCallbacks.values) callback.target,
      if (_entryPoint != null) _entryPoint.function,
    };
    if (runtime == null && selection.unwindsTo(roots) ||
        !_boundaries.hasLifecycle && selection.unwindsTo(nativeEntries)) {
      throw ArgumentError(
        'An escaping Dart failure requires an explicit runtime entry lifecycle.',
      );
    }
    for (final function in runtime?.nonAllocating ?? const []) {
      if (selected.contains(function)) selection.checkNonAllocating(function);
    }
    return PreparedProgram._(
      this,
      facts,
      selection,
      selected,
      persistent,
      .unmodifiable(activeCallbacks),
    );
  }
}

/// Closed definitions, target layouts and bindings for one immutable program.
///
/// Only [ProgramPreparation] can construct this result. Its source identity and
/// target cannot be exchanged; extending the source analysis invalidates it.
/// Emission may assign locations and addresses but cannot add dependencies.
final class PreparedProgram._(
  final ProgramPreparation _input,
  final ProgramCallFacts _facts,
  final ProgramSelection _selection,
  Set<FunctionTarget> selected,
  final bool _persistent,
  final Map<
    NativeCallbackTarget,
    ({FunctionTarget address, FunctionTarget target})
  >
  _callbacks,
) {
  /// The exact source input to the converged analysis.
  IrProgram get program => _input.program;

  /// Runtime entries checked against this exact rewritten program, if supplied.
  HeapRuntime? get runtime => _input._runtime;

  /// The platform used for layout and native ABI selection.
  Target get target => _input.target;

  /// Definitions retained after source and generated dependencies converge.
  late final Set<FunctionTarget> definitions;

  final FunctionTarget? _cleanup = _input._boundaries.cleanup;
  late final Set<String> _nativeNames;

  this {
    definitions = .unmodifiable({
      ...selected,
      ..._selection.functions.keys,
      ..._selection.primitives,
      ..._selection.layouts.nativeCalls.entries.keys,
      ?_cleanup,
    });
    final names = <String>{};
    for (final entry in _input._imports.entries) {
      if (definitions.contains(entry.key)) {
        names.add(target.nativeSymbol(entry.value.symbol));
      }
    }
    for (final body in _selection.functions.values) {
      for (final operation in body.instructions.values.expand(
        (values) => values,
      )) {
        if (operation case NativeSymbolAddress(:final reference)) {
          final name = _input._nativeSymbols[reference];
          if (name == null || name.isEmpty || name.contains('\u0000')) {
            throw ArgumentError(
              'Unbound native address: ${reference.assetId}::${reference.symbol}',
            );
          }
          names.add(target.nativeSymbol(name));
        }
      }
    }
    if (target.operatingSystem == .macos &&
        _selection.primitives.any(
          (function) => _input._runtime?.primitives[function] == .clock,
        )) {
      names.add('.dartc.clock');
    }
    _nativeNames = .unmodifiable(names);
  }
}

/// Internal consumption of a closed program; absent from the public entry.
extension PreparedProgramEmission on PreparedProgram {
  ProgramSelection get selection => _selection;
  Map<FunctionTarget, NativeImport> get imports => _input._imports;
  Map<FunctionTarget, NativeExport> get exports => _input._boundaries.exports;
  Map<NativeCallbackTarget, ({FunctionTarget address, FunctionTarget target})>
  get callbacks => _callbacks;
  Map<NativeReference, String> get nativeSymbols => _input._nativeSymbols;
  ({FunctionTarget function, String symbol})? get entryPoint =>
      _input._entryPoint;
  bool get persistent => _persistent;
  FunctionTarget? get cleanup => _cleanup;

  void checkTarget(Target target) {
    if (this.target != target) {
      throw ArgumentError('Prepared program target differs from $target.');
    }
    _facts.checkProgram(program);
  }

  void checkStackMapContexts({required bool hasContexts}) {
    if (_facts case final ProgramFlowFacts facts) {
      facts.checkStackMapContexts(runtime?.stackContext, hasContexts: hasContexts);
    }
  }

  void checkNativeSymbol(String name) {
    if (!_nativeNames.contains(name)) {
      throw StateError('Unprepared native dependency: $name');
    }
  }
}
