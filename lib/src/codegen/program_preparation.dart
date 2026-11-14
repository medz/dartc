import 'package:dartc/abi.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/target.dart';

import 'native_bindings.dart';
import 'program_selection.dart';
import 'program_layout.dart';
import 'heap_plan.dart';
import 'heap_runtime.dart';
import 'stack_traces.dart';
import 'checked_casts.dart';
import 'member_calls.dart';
import 'numeric_operations.dart';
import 'global_storage.dart';
import 'instance_storage.dart';
import 'closure_storage.dart';
import 'string_storage.dart';
import 'list_storage.dart';
import 'record_storage.dart';
import 'suspension_functions.dart';

/// A target preparation step, either closed or requiring more source facts.
sealed class const PreparationResult();

/// Source calls and instance classes discovered during target preparation.
///
/// Extend the analysis of the same program with these facts, then prepare again.
/// Calls admit all values allowed by their declared parameter types.
final class PreparationDependencies._(
  Iterable<FunctionTarget> calls,
  Iterable<ClassType> instantiatedTypes,
) extends PreparationResult {
  /// Calls introduced by generated support code.
  final Set<FunctionTarget> calls = .unmodifiable(calls);

  /// Classes instantiated without a source constructor call.
  final Set<ClassType> instantiatedTypes = .unmodifiable(instantiatedTypes);
}

/// Binds native entries and prepares storage from immutable source facts.
///
/// This stage does not run source analysis. A driver supplies current facts,
/// processes [PreparationDependencies], and repeats until [PreparedProgram].
/// Runtime source definitions must be supplied with the input program.
final class ProgramPreparation(
  /// The output platform used for layouts and native bindings.
  final Target target,
  IrProgram source, {
  Iterable<FunctionTarget> roots = const [],
  Map<FunctionTarget, NativeExport> exports = const {},
  Map<FunctionTarget, NativeImport> imports = const {},
  Map<NativeReference, String> nativeSymbols = const {},
  ({FunctionTarget function, String symbol})? entryPoint,
  HeapRuntime? runtime,
}) {
  /// The source graph after native boundary bridges have been registered.
  late final IrProgram program;

  /// Independently callable source, export and process entries.
  late final Set<FunctionTarget> roots;

  /// Metadata classes materialized by generated code.
  Iterable<ClassType> get instantiatedTypes => TypeMetadata.fields.keys;

  final _nativeSymbols = Map<NativeReference, String>.unmodifiable(
    nativeSymbols,
  );
  final _entryPoint = entryPoint;
  final _runtime = runtime;
  late final NativeBindings _bindings;

  this {
    final entries = {
      ...roots,
      ...exports.keys,
      if (entryPoint != null) ...[
        entryPoint.function,
        ?runtime?.processExitCode,
      ],
    };
    if (entries.isEmpty || exports.keys.any(imports.containsKey)) {
      throw ArgumentError(
        'Expected roots and distinct native imports and exports.',
      );
    }
    for (final entry in entries) {
      if (source.implementationOf(entry) == null) {
        throw ArgumentError('Missing entry definition: ${entry.name}');
      }
    }
    if (entryPoint case (:final function, :final symbol)) {
      final body = source.implementationOf(function);
      if (symbol.isEmpty || symbol.contains('\u0000')) {
        throw ArgumentError.value(symbol, 'entryPoint.symbol');
      }
      if (body is! IrFunction ||
          (body.bodyKind != .synchronous && body.bodyKind != .asynchronous) ||
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
    _bindings = NativeBindings(source, imports, exports, entries);
    program = _bindings.program;
    this.roots = .unmodifiable({...entries, ..._bindings.exports.keys});
  }

  /// Prepares one dependency-closed step using facts for [program].
  ///
  /// Facts for another graph, or facts invalidated by analysis changes, fail.
  /// A rewrite requires a new preparation and a new analysis from its roots.
  PreparationResult prepare(CallTypeFacts facts) {
    facts.checkProgram(this.program);
    if (roots.any((root) => !facts.admitsUnknownCall(root))) {
      throw ArgumentError('Call facts must cover every preparation root.');
    }
    final program = this.program;
    final runtime = _runtime;
    final imports = _bindings.imports;
    final callbacks = _bindings.callbacks;
    final callbackGetters = {
      for (final entry in callbacks.entries) entry.value.address: entry.key,
    };
    final sourceDefinitions = facts.definitions;
    final selected = sourceDefinitions.toSet();
    final heap = HeapPlan(runtime: runtime);
    final traces = StackTraces(runtime);
    final casts = CheckedCasts();
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
    final strings = StringStorage(
      source: program.classes
          .where((c) => c.type == ValueType.string)
          .firstOrNull,
    );
    final arithmetic = NumericOperations(
      floatingRemainder: runtime?.floatingRemainder,
      floatingModulo: runtime?.floatingModulo,
      argumentError: constructor(.argumentError),
      unsupportedError: constructor(.unsupportedError),
    );
    final constantLists = bodies.any(
      (body) => body.sequenceConstants.any(
        (value) => (value.type as ClassType).declaration == CoreTypes.list,
      ),
    );
    final lists = ListStorage(program.classes);
    // Codegen materializes these instances without source constructor calls.
    final instantiatedTypes = [
      ...TypeMetadata.fields.keys,
      if (constantLists) ...[lists.type, lists.buffer],
    ];
    final records = RecordStorage(
      program.classes,
      bodies.expand((body) => body.recordTypes),
    );
    final globals = GlobalStorage(
      bodies,
      lateError: lateErrorType == null ? null : constructor(lateErrorType),
    );
    final instances = InstanceStorage(
      bodies,
      lateError: lateErrorType == null ? null : constructor(lateErrorType),
    );
    for (final body in bodies) {
      for (final block in body.blocks) {
        final operations = switch (block.end) {
          Invoke(:final operation) => block.instructions.followedBy([
            operation,
          ]),
          _ => block.instructions,
        };
        for (final operation in operations) {
          arithmetic.callFor(operation);
        }
      }
    }
    final helpers = [
      ...arithmetic.functions,
      ...globals.functions,
      ...instances.functions,
    ];
    if (!globals.isEmpty) selected.add(globals.address);
    final requiredTypes = {
      ...instantiatedTypes,
      for (final function in helpers) ...function.instantiatedClasses,
    };
    if (requiredTypes.any((type) => !facts.instantiates(type))) {
      return PreparationDependencies._(const {}, requiredTypes);
    }
    final members = MemberCalls(
      program,
      sourceDefinitions,
      records: records,
      instantiatedTypes: requiredTypes,
      callTypes: facts,
    );
    final functions = [...bodies, ...helpers];
    final suspensions = SuspensionFunctions(functions);
    final closures = ClosureStorage(
      [...sourceBodies, ...helpers, ...suspensions.entries],
      boundMethods: [
        ...members.tearOffTargets,
        ...suspensions.entries.map((entry) => entry.target),
      ],
      lateFailure: instances.failure?.target,
    );
    final layouts = ProgramLayout(
      [
        ...casts.classes,
        ...arithmetic.classes,
        ...program.classes,
        if (!globals.isEmpty) globals.declaration,
        ...closures.classes,
        ...suspensions.classes,
      ],
      nativeLayout: NativeLayout(target),
      functions: functions,
      instanceStorage: instances,
      closureStorage: closures,
      stringStorage: strings,
      listStorage: lists,
      recordStorage: records,
      typeRuntime: runtime?.types,
      referencedClasses: [
        ...instantiatedTypes,
        for (final declaration in [
          ...casts.classes,
          ...arithmetic.classes,
          if (!globals.isEmpty) globals.declaration,
          ...closures.classes,
          ...suspensions.classes,
          ?records.declaration,
        ])
          declaration.type,
        for (final function in [...sourceBodies, ...helpers])
          ...function.referencedClasses,
      ],
    );
    final selection = ProgramSelection(
      layouts,
      heap,
      traces,
      casts,
      members,
      arithmetic,
      globals,
      instances,
      suspensions: suspensions,
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
          declaration == globals.address ||
          heap.primitives.contains(declaration)) {
        continue;
      }
      if (declaration == runtime?.types?.projection) {
        selection.include(layouts.relations.projection);
      } else if (function is! IrFunction) {
        throw ArgumentError(
          'Definition has no body: ${declaration.library}::'
          '${declaration.owner == null ? '' : '${declaration.owner!.dartName}.'}'
          '${declaration.name}',
        );
      } else {
        selection.include(function);
      }
    }
    final calls = {
      for (final body in selection.functions.values) ...body.invocations.values,
    };
    final activeCallbacks = {
      for (final entry in callbacks.entries)
        if (calls.contains(entry.value.address)) entry.key: entry.value,
    };
    final persistent =
        activeCallbacks.isNotEmpty ||
        !globals.isEmpty && globals.hasReferences(layouts);
    final missing = selection.close(persistent: persistent);
    for (final target in missing) {
      if (program.implementationOf(target) == null) {
        throw ArgumentError('Missing support dependency: ${target.name}');
      }
    }
    final additional = {
      ...missing,
      for (final callback in activeCallbacks.values) ...[
        callback.address,
        callback.target,
      ],
      for (final target in selection.implicitCalls)
        if (program.implementationOf(target) is IrFunction) target,
    }.where((target) => !facts.admitsUnknownCall(target)).toSet();
    if (additional.isNotEmpty) {
      return PreparationDependencies._(additional, requiredTypes);
    }
    if (missing.isNotEmpty) {
      throw StateError(
        'Required source calls were not selected: '
        '${missing.map((target) => target.name).join(', ')}',
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
  final CallTypeFacts _facts,
  final ProgramSelection _selection,
  Set<FunctionTarget> selected,
  final bool _persistent,
  final Map<
    NativeCallbackEntry,
    ({FunctionTarget address, FunctionTarget target})
  >
  _callbacks,
) extends PreparationResult {
  /// The exact source input to the converged analysis.
  IrProgram get program => _input.program;

  /// The platform used for layout and native ABI selection.
  Target get target => _input.target;

  /// Definitions retained after source and generated dependencies converge.
  late final Set<FunctionTarget> definitions;

  final FunctionTarget? _cleanup = _persistent && _input._entryPoint == null
      ? FunctionTarget(null, 'release', .voidType, [])
      : null;
  late final Set<String> _nativeNames;

  this {
    definitions = .unmodifiable({
      ...selected,
      ..._selection.functions.keys,
      ..._selection.primitives,
      ..._selection.layouts.nativeCalls.signatures.keys,
      if (_selection.capture) _selection.traces.capture,
      ?_cleanup,
    });
    final names = <String>{};
    for (final entry in _input._bindings.imports.entries) {
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
  Map<FunctionTarget, NativeImport> get imports => _input._bindings.imports;
  Map<FunctionTarget, NativeExport> get exports => _input._bindings.exports;
  Map<NativeCallbackEntry, ({FunctionTarget address, FunctionTarget target})>
  get callbacks => _callbacks;
  Map<NativeReference, String> get nativeSymbols => _input._nativeSymbols;
  ({FunctionTarget function, String symbol})? get entryPoint =>
      _input._entryPoint;
  HeapRuntime? get runtime => _input._runtime;
  bool get persistent => _persistent;
  FunctionTarget? get cleanup => _cleanup;

  void checkTarget(Target target) {
    if (this.target != target) {
      throw ArgumentError('Prepared program target differs from $target.');
    }
    _facts.checkProgram(program);
  }

  void checkNativeSymbol(String name) {
    if (!_nativeNames.contains(name)) {
      throw StateError('Unprepared native dependency: $name');
    }
  }
}
