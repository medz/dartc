import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/layout.dart' show RuntimeContext;

import 'entry_lifecycle.dart';
import 'heap_runtime.dart';
import 'native_call_lowering.dart';

/// Introduces ordinary IR bridges before semantic analysis of native boundaries.
///
/// [imports] supplies signatures without resolving external symbols. [roots]
/// retain the Dart calling convention and a caller's valid activation. Native
/// host entries use exports, callbacks or the explicit process entry.
final class NativeBoundaries {
  /// The source graph including native conversion and callback bodies.
  late final IrProgram program;

  /// Independent entries after native argument conversion has been introduced.
  late final Set<FunctionTarget> roots;

  /// Native callees and their original declaration and platform signature.
  late final Map<FunctionTarget, NativeImportEntry> imports;

  /// Public native symbols attached to their actual entry bodies.
  late final Map<FunctionTarget, NativeExport> exports;

  /// Address providers and ABI entries for checked callback declarations.
  late final Map<
    NativeCallbackTarget,
    ({FunctionTarget address, FunctionTarget target})
  >
  callbacks;
  final _functions = <IrFunction>[];
  final _exportOrigins = <FunctionTarget, FunctionTarget>{};
  FunctionTarget? _processEntry, _cleanup;
  bool _hasLifecycle = false, _persistent = false;
  NativeData? _runtimeContext;
  FunctionTarget? _publicationFailure;
  final _exportEntries = <FunctionTarget, NativeExportEntry>{};
  final _processEntries = <FunctionTarget, FunctionTarget>{};
  final _knownCallbacks =
      <
        NativeCallbackTarget,
        ({FunctionTarget address, FunctionTarget target})
      >{};
  final _linkedImports = <FunctionTarget>{};
  final _linkedExports = <FunctionTarget>{};
  final _linkedCallbacks = <NativeCallbackTarget>{};
  FunctionTarget? _contextQuery, _knownCleanup;

  /// Ordinary process body including draining, status and cleanup.
  FunctionTarget? get processEntry => _processEntry;

  /// Ordinary module finalizer, whose body participates in the same analysis.
  FunctionTarget? get cleanup => _cleanup;

  /// Whether native entries already contain their runtime lifecycle.
  bool get hasLifecycle => _hasLifecycle;

  /// Runtime state owned by this module, never inferred from native ABI binding.
  NativeData? get runtimeContext => _runtimeContext;

  /// Checked terminal primitive used before publication without an active record.
  FunctionTarget? get publicationFailure => _publicationFailure;

  /// Whether entries share module-owned runtime context storage.
  bool get persistent => _persistent;

  new(
    IrProgram source, {
    Map<FunctionTarget, NativeSignature> imports = const {},
    Iterable<FunctionTarget> leafImports = const [],
    Iterable<FunctionTarget> nonAllocatingImports = const [],
    Map<FunctionTarget, NativeExport> exports = const {},
    Iterable<FunctionTarget> roots = const [],
  }) {
    final existing = source.nativeBoundaries;
    for (final body in source.functions) {
      for (final block in body.blocks) {
        for (final operation in [
          ...block.instructions,
          if (block.end case Invoke(:final operation)) operation,
        ]) {
          if (operation case NativeDataAddress(:final declaration)
              when declaration.contextOwner != null &&
                  !identical(declaration, existing?.context)) {
            throw ArgumentError(
              'A rewritten native lifecycle must preserve its current boundary bindings.',
            );
          }
        }
      }
    }
    if (existing != null) {
      existing.checkProgram(source);
      if (existing.context case final context?
          when context.bytes.length != RuntimeContext.size ||
              context.alignment < 8 ||
              !context.writable) {
        throw ArgumentError(
          'Native lifecycle requires writable context storage.',
        );
      }
      _exportEntries.addAll(existing.exports);
      _processEntries.addAll(existing.processes);
      _knownCallbacks.addAll(existing.callbacks);
      _runtimeContext = existing.context;
      _contextQuery = existing.contextQuery;
      _publicationFailure = existing.failure;
      _knownCleanup = existing.cleanup;
      _persistent = existing.persistent;
      _hasLifecycle = existing.context != null;
      if (_hasLifecycle) {
        _linkedImports.addAll(existing.imports.keys);
        _linkedExports.addAll(existing.exports.values.map((e) => e.entry));
        _linkedCallbacks.addAll(existing.callbacks.keys);
      }
    }
    final leaves = leafImports.toSet();
    final critical = nonAllocatingImports.toSet();
    if ({
      ...leaves,
      ...critical,
    }.any((target) => !imports.containsKey(target))) {
      throw ArgumentError('Native promises require an imported declaration.');
    }
    final entries = roots.toSet();
    final sourceEntries = {...entries, ...exports.keys};
    if (sourceEntries.isEmpty || exports.keys.any(imports.containsKey)) {
      throw ArgumentError(
        'Expected roots and distinct native imports and exports.',
      );
    }
    for (final entry in sourceEntries) {
      if (source.implementationOf(entry) == null) {
        throw ArgumentError('Missing entry definition: ${entry.name}');
      }
    }
    final nativeImports = <FunctionTarget, NativeImportEntry>{
      ...?existing?.imports,
    };
    final nativeExports = <FunctionTarget, NativeExport>{};
    final nativeCallbacks =
        <
          NativeCallbackTarget,
          ({FunctionTarget address, FunctionTarget target})
        >{};
    final externals = source.externals.toList();
    for (final MapEntry(key: target, value: binding) in imports.entries) {
      if (existing?.imports[target] case final prior?
          when prior.source != target) {
        throw ArgumentError(
          'Native import configuration requires its original source declaration.',
        );
      }
      final prior = existing?.imports.entries
          .where((entry) => entry.value.source == target)
          .singleOrNull;
      if (prior != null) {
        if (prior.value.signature != binding ||
            prior.value.isLeaf != leaves.contains(target) ||
            prior.value.isNonAllocating != critical.contains(target)) {
          throw ArgumentError(
            'A native import cannot change its existing ABI or effect promises.',
          );
        }
        continue;
      }
      final declaration = source.implementationOf(target);
      if (declaration is! IrExternal ||
          target.kind.hasReceiver ||
          !FfiTypes.canCall(binding, target.signature)) {
        throw ArgumentError(
          'Native import requires a matching external declaration: ${target.name}',
        );
      }
      final raw = _needsBridge(binding)
          ? _bridge(target, intoDart: false)
          : target;
      final contract = (
        source: target,
        signature: binding,
        isLeaf: leaves.contains(target),
        isNonAllocating: critical.contains(target),
      );
      externals.remove(declaration);
      externals.add(
        declaration.bindNative(
          raw,
          isLeaf: contract.isLeaf,
          isNonAllocating: contract.isNonAllocating,
          resultStorage: switch (binding.result) {
            final NativeCompoundType type => type,
            _ => null,
          },
        ),
      );
      nativeImports[raw] = contract;
    }
    for (final MapEntry(key: target, value: binding) in exports.entries) {
      final signature = binding.signature;
      final prior = existing?.exports.entries
          .where((entry) => entry.key == target || entry.value.entry == target)
          .singleOrNull;
      if (prior != null) {
        if (prior.value.signature != signature) {
          throw ArgumentError(
            'A native export cannot change its existing ABI.',
          );
        }
        nativeExports[prior.value.entry] = binding;
        _exportOrigins[target] = prior.value.entry;
        continue;
      }
      if (!FfiTypes.canExport(signature, target.signature)) {
        throw ArgumentError('Native signature mismatch: ${target.name}');
      }
      final converted = _needsBridge(signature)
          ? _bridge(target, intoDart: true)
          : target;
      nativeExports[converted] = binding;
      _exportOrigins[target] = converted;
      _exportEntries[target] = (entry: converted, signature: signature);
    }
    // Programs without callback entries need no callback reachability analysis.
    late final selected = reachableDefinitions(source, sourceEntries);
    for (final body in source.functions) {
      for (final block in body.blocks) {
        for (final instruction in [
          ...block.instructions,
          if (block.end case Invoke(:final operation)) operation,
        ].whereType<NativeCallbackAddress>()) {
          if (!selected.contains(body.target)) break;
          final definition = instruction.target;
          if (nativeCallbacks.containsKey(definition)) continue;
          if (_knownCallbacks[definition] case final binding?) {
            nativeCallbacks[definition] = binding;
            continue;
          }
          final signature = definition.dartSignature;
          final target = FunctionTarget(
            null,
            'callback${nativeCallbacks.length}',
            signature.result,
            [
              if (definition is ClosureCallbackTarget) ValueType.integer,
              ...signature.parameters,
            ],
          );
          final entry = Block(target.parameterTypes);
          final result = entry.emit(switch (definition) {
            StaticCallbackTarget(:final function) => DirectCall(
              function,
              function.signature.bind(
                entry.parameters,
                {},
                (i) => source.implementationOf(function)!.defaults[i]!,
              ),
            ),
            ClosureCallbackTarget(:final lookup) => FunctionCall(
              entry.emit(
                UncheckedCast(
                  entry.emit(DirectCall(lookup, [entry.parameters.first])),
                  definition.dartSignature,
                ),
              ),
              entry.parameters.skip(1),
            ),
          });
          entry.finish(
            result.type == .never
                ? Unreachable(result)
                : Return(signature.result == .voidType ? null : result),
          );
          _functions.add(IrFunction(target, [entry]));
          final converted = _needsBridge(definition.signature)
              ? _bridge(target, intoDart: true)
              : target;
          final address = FunctionTarget(
            null,
            'callbackAddress${nativeCallbacks.length}',
            .integer,
            [],
          );
          externals.add(IrExternal(address));
          nativeCallbacks[definition] = (
            address: address,
            target: _catchCallback(converted, definition),
          );
          _knownCallbacks[definition] = nativeCallbacks[definition]!;
        }
      }
    }
    this.roots = .unmodifiable({...entries, ...nativeExports.keys});
    this.imports = .unmodifiable(nativeImports);
    this.exports = .unmodifiable(nativeExports);
    callbacks = .unmodifiable(nativeCallbacks);
    final unchanged =
        _functions.isEmpty &&
        nativeImports.length == (existing?.imports.length ?? 0) &&
        _exportEntries.length == (existing?.exports.length ?? 0) &&
        _knownCallbacks.length == (existing?.callbacks.length ?? 0);
    program = unchanged
        ? source
        : IrProgram(
            source.classes,
            [...source.functions, ..._functions],
            globals: source.globals,
            externals: externals,
            nativeBoundaries: _bindings(),
            executionShapes: source.executionShapes,
          );
  }

  /// Installs actual runtime calls before whole-program specialization.
  new withLifecycle(
    NativeBoundaries source,
    HeapRuntime runtime, {
    FunctionTarget? processEntry,
  }) {
    if (processEntry != null && !source.roots.contains(processEntry)) {
      throw ArgumentError('Process body must be an actual boundary root.');
    }
    _publicationFailure = runtime.primitives.entries
        .where((entry) => entry.value == .fail)
        .map((entry) => entry.key)
        .single;
    if (source.hasLifecycle &&
        (source.publicationFailure != _publicationFailure ||
            source._contextQuery != runtime.context)) {
      throw ArgumentError(
        'Existing native entries belong to a different runtime binding.',
      );
    }
    _hasLifecycle = true;
    _contextQuery = runtime.context;
    _exportEntries.addAll(source._exportEntries);
    _processEntries.addAll(source._processEntries);
    _knownCallbacks.addAll(source._knownCallbacks);
    _knownCleanup = source._knownCleanup;
    _persistent =
        source.persistent ||
        source.exports.isNotEmpty ||
        source.callbacks.isNotEmpty;
    final context = _runtimeContext =
        source.runtimeContext ??
        NativeData(
          List.filled(RuntimeContext.size, 0),
          alignment: 8,
          contextOwner: NativeContextOwner(
            runtime.context,
            publicationFailure!,
          ),
        );
    final lifecycle = EntryLifecycle(
      runtime,
      globalRoots: (block) => block.emit(ModuleRootsAddress()),
      context: context,
    );
    final externals = source.program.externals.toList();
    if (source.program.implementationOf(publicationFailure!) == null) {
      externals.add(
        runtime.program.implementationOf(publicationFailure!) as IrExternal,
      );
    }
    final importBridges = <IrFunction>[];
    imports = Map.unmodifiable({
      for (final entry in source.imports.entries)
        if (entry.value.isLeaf ||
            entry.value.isNonAllocating ||
            source._linkedImports.contains(entry.key))
          entry.key: entry.value
        else
          (() {
            final original = entry.key;
            final native = FunctionTarget(
              null,
              'nativeImport',
              original.returnType,
              original.parameterTypes,
            );
            final declaration = externals.singleWhere(
              (e) => e.target == original,
            );
            externals.remove(declaration);
            externals.add(
              IrExternal(
                native,
                effects: declaration.effects,
                terminates: declaration.terminates,
                memory: declaration.memory,
                capturesArguments: declaration.capturesArguments,
              ),
            );
            importBridges.add(
              NativeCallLowering.importBridge(
                original,
                native,
                managedContext: context,
                failure: publicationFailure!,
              ),
            );
            return native;
          })(): entry.value,
    });
    final replaced = <FunctionTarget, FunctionTarget>{};
    exports = Map.unmodifiable({
      for (final entry in source.exports.entries)
        (replaced[entry.key] = source._linkedExports.contains(entry.key)
                ? entry.key
                : lifecycle.wrap(entry.key)):
            entry.value,
    });
    for (final entry in _exportEntries.entries.toList()) {
      _exportEntries[entry.key] = (
        entry: replaced[entry.value.entry] ?? entry.value.entry,
        signature: entry.value.signature,
      );
    }
    for (final entry in source._exportOrigins.entries) {
      replaced[entry.key] = replaced[entry.value]!;
    }
    callbacks = Map.unmodifiable({
      for (final entry in source.callbacks.entries)
        entry.key: (
          address: entry.value.address,
          target: source._linkedCallbacks.contains(entry.key)
              ? entry.value.target
              : lifecycle.wrap(entry.value.target, callback: entry.key),
        ),
    });
    _knownCallbacks.addAll(callbacks);
    _linkedImports.addAll(imports.keys);
    _linkedExports.addAll(_exportEntries.values.map((entry) => entry.entry));
    _linkedCallbacks.addAll(_knownCallbacks.keys);
    if (processEntry != null) {
      final original = _processEntries.entries
          .where(
            (entry) => entry.key == processEntry || entry.value == processEntry,
          )
          .singleOrNull;
      _processEntry =
          original?.value ?? lifecycle.wrap(processEntry, process: true);
      _processEntries[original?.key ?? processEntry] = _processEntry!;
      replaced[processEntry] = _processEntry!;
    } else if (_persistent) {
      _cleanup = _knownCleanup ?? lifecycle.close();
      _knownCleanup = _cleanup;
    }
    roots = Set.unmodifiable({
      for (final root in source.roots) replaced[root] ?? root,
      ...exports.keys,
      ?_cleanup,
    });
    program = IrProgram(
      source.program.classes,
      [
        for (final function in source.program.functions)
          if (source.hasLifecycle || function.target != runtime.context)
            function,
        if (runtime.context case final query? when !source.hasLifecycle)
          (() {
            final entry = Block();
            entry.finish(Return(entry.emit(NativeDataAddress(context))));
            return IrFunction(query, [entry]);
          })(),
        ...importBridges,
        ...lifecycle.functions,
      ],
      globals: source.program.globals,
      externals: externals,
      nativeBoundaries: _bindings(),
      executionShapes: source.program.executionShapes,
    );
  }

  NativeBoundaryBindings _bindings() => NativeBoundaryBindings(
    exports: _exportEntries,
    imports: imports,
    callbacks: _knownCallbacks,
    processes: _processEntries,
    context: runtimeContext,
    contextQuery: _contextQuery,
    failure: publicationFailure,
    cleanup: _knownCleanup,
    persistent: persistent,
  );

  bool _needsBridge(NativeSignature signature) =>
      (signature.result.isVoid ||
          signature.result is NativePointerType ||
          signature.result is NativeCompoundType) ||
      signature.parameters.any(
        (type) => type is NativePointerType || type is NativeCompoundType,
      );

  FunctionTarget _catchCallback(
    FunctionTarget body,
    NativeCallbackTarget callback,
  ) {
    final target = FunctionTarget(
      null,
      'callbackResult${_functions.length}',
      body.returnType,
      body.parameterTypes,
    );
    final entry = Block(target.parameterTypes);
    final returned = Block(
      body.returnType == .voidType ? [] : [body.returnType],
    );
    final failed = Block();
    final call = DirectCall(body, entry.parameters);
    entry.finish(
      Invoke(
        call,
        onReturn: Jump(returned, body.returnType == .voidType ? [] : [call]),
        onThrow: Jump(failed),
      ),
    );
    returned.finish(Return(returned.parameters.firstOrNull));
    final Value? fallback;
    if (callback.signature.result case final NativeCompoundType storage) {
      final zero = failed.emit(
        NativeLocalStorage(storage, zeroInitialize: true),
      );
      failed.emit(CopyNative(entry.parameters.first, zero, storage));
      fallback = null;
    } else if (callback.signature.result is NativePointerType) {
      fallback = const Constant.integer(0);
    } else {
      fallback = callback.exceptionalReturn;
    }
    failed.finish(Return(fallback));
    _functions.add(IrFunction(target, [entry, returned, failed]));
    return target;
  }

  FunctionTarget _bridge(FunctionTarget dart, {required bool intoDart}) {
    bool compound(ValueType type) =>
        type is ClassType && type.nativeType is NativeCompoundType;
    ValueType rawType(ValueType type) =>
        FfiTypes.isPointer(type) || compound(type) ? .integer : type;
    final resultCompound = compound(dart.returnType);
    final raw = FunctionTarget(
      null,
      'native${_functions.length}',
      resultCompound ? .voidType : rawType(dart.returnType),
      [
        if (resultCompound) ValueType.integer,
        ...dart.parameterTypes.map(rawType),
      ],
    );
    final (source, destination) = intoDart ? (raw, dart) : (dart, raw);
    final entry = Block(source.parameterTypes);
    final offset = intoDart && resultCompound ? 1 : 0;
    final resultStorage = !intoDart && resultCompound
        ? entry.emit(NativeView(dart.returnType as ClassType))
        : null;
    final arguments = <Value>[
      if (resultStorage != null) entry.emit(NativeAddress(resultStorage)),
    ];
    for (final (i, type) in dart.parameterTypes.indexed) {
      final value = entry.parameters[i + offset];
      arguments.add(
        FfiTypes.isPointer(type)
            ? entry.emit(
                intoDart
                    ? PointerFromAddress(value, type as ClassType)
                    : PointerAddress(value),
              )
            : compound(type)
            ? entry.emit(
                intoDart
                    ? NativeView(type as ClassType, address: value, copy: true)
                    : NativeAddress(value),
              )
            : value,
      );
    }
    Value result = entry.emit(DirectCall(destination, arguments));
    if (!intoDart) {
      for (final value in entry.parameters) {
        entry.emit(KeepAlive(value));
      }
    }
    if (resultCompound) {
      if (intoDart) {
        entry.emit(
          CopyNative(
            entry.parameters.first,
            entry.emit(NativeAddress(result)),
            (dart.returnType as ClassType).nativeType!,
          ),
        );
        entry.emit(KeepAlive(result));
        entry.finish(const Return());
      } else {
        entry.finish(Return(resultStorage!));
      }
    } else {
      if (FfiTypes.isPointer(dart.returnType)) {
        result = entry.emit(
          intoDart
              ? PointerAddress(result)
              : PointerFromAddress(result, dart.returnType as ClassType),
        );
      }
      entry.finish(Return(dart.returnType == .voidType ? null : result));
    }
    _functions.add(IrFunction(source, [entry]));
    return raw;
  }
}
