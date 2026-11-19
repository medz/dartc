import 'dart:ffi' show Int64, Uint16;

import 'package:dartc/ir.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/layout.dart';

import 'flow_memory.dart';
import 'flow_value.dart';
import 'integer_range.dart';
import 'memory_layout.dart';
import 'state_map.dart';

/// Normal and exceptional state, including the actual thrown values.
final class const FlowResult({
  final FlowValue value = const .bottom(),
  final FlowState? normal,
  final FlowState? exceptional,

  /// Integer bounds on the caller's existing SSA values after a normal return.
  final Map<Value, FlowIntegerRange> normalRanges = const {},

  /// Failure may disappear only when the allocation itself is eliminated.
  final bool allocationFailureOnly = false,

  /// Effects performed by this transfer itself, excluding source callees.
  final Set<Effect> effects = const {},
  FlowValue? exception,
  FlowValue? stackTrace,
}) {
  final FlowValue? _exception = exception;
  final FlowValue? _stackTrace = stackTrace;

  /// Whether a failure remains obligatory even when the result is unused.
  bool get hasSemanticFailure => exceptional != null && !allocationFailureOnly;

  /// An unreachable exceptional exit carries no thrown value.
  FlowValue get exception =>
      exceptional == null ? const .bottom() : _exception ?? _unknownException;

  /// The source trace, or an unknown trace created by a new language error.
  FlowValue get stackTrace =>
      exceptional == null ? const .bottom() : _stackTrace ?? _unknownTrace;
}

final _unknownException = FlowValue.unknown(ValueType.object);
final _unknownTrace = FlowValue.unknown(ValueType.stackTrace);

/// Queries a source call in the program's shared worklist.
typedef FlowInvoke = FlowResult Function(
  FunctionTarget target,
  List<FlowValue> arguments,
  FlowState input,
);

/// Queries a callable value without discarding its captured environment.
typedef FlowCall = FlowResult Function(
  FlowValue function,
  List<FlowValue> arguments,
  FlowState input,
);

/// Storage read or written by a body and its statically known callees.
typedef FlowStorageAccess = ({
  Set<InstanceField> fields,
  Set<GlobalVariable> globals,
  Set<NativeData> data,
  Set<ModuleObject> modules,
  bool context,
  bool cells,
  bool memory,
  bool writes,
  bool exposed,
  bool rawWrites,
});

/// One stable external address and its entry-state byte facts.
typedef FlowMemoryBinding = ({FlowObject allocation, FlowMemory memory});

Map<NativeData, FlowMemoryBinding> _bindNativeData(IrProgram program) {
  final bindings = <NativeData, FlowMemoryBinding>{};
  for (final function in program.functions) {
    for (final block in function.blocks) {
      for (final operation in [
        ...block.instructions.whereType<NativeDataAddress>(),
        if (block.end case Invoke(operation: final NativeDataAddress address))
          address,
      ]) {
        bindings.putIfAbsent(
          operation.declaration,
          () => (
            allocation: FlowObject(operation, program),
            memory: FlowMemory.bytes(operation.declaration.bytes),
          ),
        );
      }
    }
  }
  return Map.unmodifiable(bindings);
}

Map<ModuleObject, FlowObject> _bindModuleObjects(IrProgram program) {
  final bindings = <ModuleObject, FlowObject>{};
  for (final function in program.functions) {
    for (final block in function.blocks) {
      for (final operation in [
        ...block.instructions.whereType<ModuleObjectReference>(),
        if (block.end case Invoke(
          operation: final ModuleObjectReference reference,
        ))
          reference,
      ]) {
        bindings.putIfAbsent(
          operation.declaration,
          () => FlowObject(operation, program),
        );
      }
    }
  }
  return Map.unmodifiable(bindings);
}

/// Storage facts at one executable program point.
///
/// Transfers return independent exit snapshots. Allocation identities and call
/// scheduling belong to the program solver, including repetition in its CFG.
final class FlowState {
  /// The immutable semantic graph whose declarations identify slots.
  final IrProgram program;

  /// Explicit output storage; absent layouts never imply host memory facts.
  final FlowMemoryLayout? memoryLayout;
  final Map<FunctionTarget, FlowMemoryBinding> _externalMemory;
  final Map<NativeData, FlowMemoryBinding> _nativeData;
  final Map<ModuleObject, FlowObject> _moduleObjects;
  final Set<GlobalVariable> _declaredGlobals;
  final Map<ClassType, IrClass> _classes;
  final Map<Object, FlowMemory> _constantMemory;
  StateMap<GlobalVariable, _Slot> _globals;
  StateMap<FlowObject, _ObjectState> _objects;
  StateMap<FlowObject, _ObjectState> _regions;
  StateMap<FlowSource, FlowValue> _addresses;
  FlowValue _escaped;
  // External-origin aliases inherited by a projected input are dependencies,
  // not evidence that this invocation exposed or retained those objects.
  FlowValue _externalAliases;
  FlowValue _nativeContext;
  StateMap<Object, StateMap<Object, bool>> _writes = const .empty();

  new(
    this.program, {
    this.memoryLayout,
    Map<FunctionTarget, FlowMemoryBinding> externalMemory = const {},
  }) : _externalMemory = Map.unmodifiable(externalMemory),
       _nativeData = _bindNativeData(program),
       _moduleObjects = _bindModuleObjects(program),
       _declaredGlobals = Set.unmodifiable(program.globals),
       _classes = Map.unmodifiable({
         for (final c in program.classes) c.type: c,
       }),
       _constantMemory = {},
       _globals = const .empty(),
       _objects = const .empty(),
       _regions = StateMap.fromEntries([
         for (final binding in externalMemory.values)
           MapEntry(
             binding.allocation,
             _ObjectState({}, memory: binding.memory),
           ),
       ]),
       _addresses = const .empty(),
       _escaped = const .bottom(),
       _externalAliases = const .bottom(),
       _nativeContext = FlowValue.unknown(.integer) {
    for (final binding in _nativeData.values) {
      _regions = _regions.withEntry(
        binding.allocation,
        _ObjectState({}, memory: binding.memory),
      );
    }
    for (final MapEntry(key: declaration, value: object)
        in _moduleObjects.entries) {
      final fields = <Object, _Slot>{};
      for (
        ClassType? type = declaration.type;
        type != null;
        type = type.superclass
      ) {
        for (final field in _class(type)?.fields ?? const <InstanceField>[]) {
          fields[field] = switch (declaration.initialFields[field]) {
            final initial? => _Slot.bound(FlowValue.constant(initial)),
            null => const _Slot.unbound(),
          };
        }
      }
      final layout = memoryLayout?.objectLayout(declaration.type);
      // Header addresses remain symbolic. Typed field bindings have one owner;
      // raw field bytes are conservative until their representation is known.
      var memory = layout == null ? null : FlowMemory(0, layout.size);
      if (memory != null) {
        memory = memory
            .forget(ObjectHeader.identityHashOffset, ObjectHeader.alignment)
            .forget(
              ObjectHeader.fieldsOffset,
              layout!.size - ObjectHeader.fieldsOffset,
            )
            .write(
              ObjectHeader.sizeOffset,
              NativeScalarType(Int64),
              FlowValue.constant(Constant.integer(layout.size)),
              memoryLayout!.nativeLayout,
            )
            .write(
              ObjectHeader.descriptorOffset,
              NativeScalarType(Int64),
              FlowValue.address(FlowAddress(declaration.type.declaration, 0)),
              memoryLayout!.nativeLayout,
            )
            .writeReference(
              ObjectHeader.typeOffset,
              FlowValue.constant(TypeConstant(declaration.type)),
            );
      }
      _objects = _objects.withEntry(
        object,
        _ObjectState(fields, memory: memory),
      );
    }
  }

  new _(
    this.program,
    this.memoryLayout,
    this._externalMemory,
    this._nativeData,
    this._moduleObjects,
    this._declaredGlobals,
    this._classes,
    this._constantMemory,
    this._globals,
    this._objects,
    this._regions,
    this._addresses,
    this._escaped,
    this._externalAliases,
    this._nativeContext,
    this._writes,
  );

  /// Shares immutable storage versions; taking a point snapshot is O(1).
  /// [resetWrites] starts a callee's execution without its caller's write history.
  FlowState copy({bool resetWrites = false, FlowValue? nativeContext}) =>
      FlowState._(
        program,
        memoryLayout,
        _externalMemory,
        _nativeData,
        _moduleObjects,
        _declaredGlobals,
        _classes,
        _constantMemory,
        _globals,
        _objects,
        _regions,
        _addresses,
        _escaped,
        _externalAliases,
        nativeContext ?? _nativeContext,
        resetWrites ? const .empty() : _writes,
      );

  /// The activation's inherited or locally bound native calling context.
  /// A callee's ABI restores its caller's binding on every completion edge.
  FlowValue get nativeContext => _nativeContext;

  /// Renames a private input graph without changing its alias topology.
  /// Fixed capabilities returned by [anchoredIdentities] must retain identity.
  FlowState mapObjects(Map<FlowObject, FlowObject> mapping) {
    if (mapping.isEmpty) return copy();
    final identities = {...allocationIdentities(const []), ...mapping.keys};
    final mapped = <FlowObject>{};
    for (final object in identities) {
      if (!mapped.add(mapping[object] ?? object)) {
        throw ArgumentError('Input object renaming must be one-to-one.');
      }
    }
    for (final object in anchoredIdentities()) {
      if ((mapping[object] ?? object) != object) {
        throw ArgumentError('Input renaming cannot change a fixed capability.');
      }
    }
    FlowObject rename(FlowObject object) => mapping[object] ?? object;
    FlowValue value(FlowValue value) => value.mapObjects(rename);
    return FlowState._(
      program,
      memoryLayout,
      _externalMemory,
      _nativeData,
      _moduleObjects,
      _declaredGlobals,
      _classes,
      _constantMemory,
      _globals.mapValues((_, slot) => slot.map(value)),
      StateMap.fromEntries([
        for (final entry in _objects.entries)
          MapEntry(rename(entry.key), entry.value.map(value)),
      ]),
      StateMap.fromEntries([
        for (final entry in _regions.entries)
          MapEntry(rename(entry.key), entry.value.map(value)),
      ]),
      _addresses.mapValues((_, address) => value(address)),
      value(_escaped),
      value(_externalAliases),
      value(_nativeContext),
      StateMap.fromEntries([
        for (final entry in _writes.entries)
          MapEntry(
            entry.key is FlowObject
                ? rename(entry.key as FlowObject)
                : entry.key,
            entry.value,
          ),
      ]),
    );
  }

  /// Capabilities whose identities are shared outside a private call input.
  Set<FlowObject> anchoredIdentities() {
    final reachable = _reachable(
      [
        _escaped,
        _externalAliases,
        _nativeContext,
        for (final object in _moduleObjects.values)
          if (_objects[object] != null) FlowValue.object(object),
        for (final slot in _globals.values) ...[slot.value, slot.initializer],
        for (final entry in _objects.entries)
          if (entry.value.captures != null ||
              entry.key.variant != null ||
              entry.key.type is FunctionType)
            FlowValue.object(entry.key),
        for (final binding in [
          ..._externalMemory.values,
          ..._nativeData.values,
        ])
          FlowValue.address(FlowAddress(FlowRegion(binding.allocation), 0)),
      ],
      expose: false,
      constants: false,
    );
    return {
      ...reachable.objects,
      for (final address in reachable.addresses)
        if (address.base case FlowRegion(:final allocation)) allocation,
      ..._unknownAliases(reachable, includeRegions: true),
    };
  }

  /// The stable address returned by a bound external getter.
  FlowValue? externalResult(FunctionTarget target) =>
      switch (_externalMemory[target]) {
        final binding? => FlowValue.address(
          FlowAddress(FlowRegion(binding.allocation), 0),
        ),
        null => null,
      };

  FlowValue _dataAddress(NativeData declaration) {
    final binding = _nativeData[declaration];
    if (binding == null || _regions[binding.allocation] == null) {
      throw StateError(
        'Module storage was not retained in this execution state.',
      );
    }
    return FlowValue.address(FlowAddress(FlowRegion(binding.allocation), 0));
  }

  FlowValue _moduleReference(ModuleObject declaration) {
    final object = _moduleObjects[declaration];
    if (object == null || _objects[object] == null) {
      throw StateError(
        'Module object was not retained in this execution state.',
      );
    }
    return FlowValue.object(object);
  }

  /// Keeps valid SSA equalities without changing stored values or prior snapshots.
  void retainSources(bool Function(FlowSource) retain) {
    _mapValues(
      (value) => resolveValue(value).withSources(value.sources.where(retain)),
    );
    for (final source in _addresses.keys) {
      if (!retain(source)) _addresses = _addresses.withoutKey(source);
    }
  }

  /// Keeps an SSA block argument paired with the storage on its incoming edge.
  void bindAddress(FlowSource parameter, FlowValue value) {
    if (value.addresses.isNotEmpty &&
        value.managedBackings.isEmpty &&
        !value.hasUnknownBacking &&
        value.types.every((type) => type == ValueType.integer)) {
      _addresses = _addresses.withEntry(parameter, value.withSources(const []));
    }
  }

  /// Applies current storage and address facts, not facts from an earlier use.
  FlowValue resolveValue(FlowValue value) {
    if (value.managedBackings.isNotEmpty || value.hasUnknownBacking) {
      value = _resolveScalarCarrier(value);
    }
    if (_addresses.isEmpty ||
        value.sources.isEmpty ||
        value.types.any((type) => type != ValueType.integer)) {
      return value;
    }
    FlowValue? address;
    List<FlowValue>? alternatives;
    for (final source in value.sources) {
      if (_addresses[source] case final known?) {
        if (address == null) {
          address = known;
        } else if (address != known) {
          (alternatives ??= [address]).add(known);
          address = address.join(known);
        }
      }
    }
    // These SSA sources equal the same value on every incoming path. Keep a
    // closed set of address bits if each source includes all of its choices.
    // An open or incomparable set keeps the conservative joined result.
    if (alternatives != null && alternatives.every(_closedAddressChoices)) {
      for (final candidate in alternatives) {
        if (alternatives.every(
          (other) =>
              other.addresses.containsAll(candidate.addresses) &&
              candidate.constants.every(
                (c) => other.constants.any(
                  (v) => v.structuralKey == c.structuralKey,
                ),
              ),
        )) {
          address = candidate.withReferences([address!.references]);
          break;
        }
      }
    }
    return address == null
        ? value
        : address.withSources(value.sources).withReferences([value.references]);
  }

  bool _closedAddressChoices(FlowValue value) =>
      value.addresses.isNotEmpty &&
      value.objects.isEmpty &&
      value.unknownTypes.isEmpty &&
      value.managedBackings.isEmpty &&
      !value.hasUnknownBacking &&
      value.rawBackingTypes.isEmpty &&
      value.addresses.every(
        (a) =>
            a.type == ValueType.integer && a.offset != null && !a.retainedBase,
      ) &&
      value.constants.every((c) => c is ScalarConstant && c.value is int);

  FlowValue _resolveScalarCarrier(FlowValue value) {
    final layout = memoryLayout?.nativeLayout;
    final payloads = <FlowValue>[];
    for (final backing in value.managedBackings) {
      final memory = _objects[backing]?.memory;
      payloads.add(
        layout == null || memory == null
            ? FlowValue.unknown(backing.type)
            : memory.read(
                ObjectHeader.fieldsOffset,
                ExecutionShapes.scalarStorageOf(backing.type),
                layout,
              ),
      );
    }
    return value.withScalarPayloads(payloads);
  }

  /// Applies path bounds to storage still equal to the checked SSA definitions.
  void refineIntegers(Map<FlowSource, FlowIntegerRange> ranges) {
    if (ranges.isEmpty) return;
    if (ranges.keys.any((source) => source.value is LoadNative)) {
      _regions = _regions.mapValues((_, region) {
        if (region.summary || region.memory == null) return region;
        final narrowed = region.memory!.refineWords(ranges, (source, value) {
          _addresses = _addresses.withEntry(source, value);
        });
        return region.withMemory(narrowed);
      });
    }
    _mapValues((value) {
      for (final source in value.sources) {
        if (ranges[source] case final range?) {
          value = value.restrictIntegers(range);
        }
      }
      return value;
    });
    _addresses = _addresses.mapValues(
      (source, value) => switch (ranges[source]) {
        final range? => value.restrictIntegers(range),
        null => value,
      },
    );
  }

  /// Narrows storage still equal to a value tested on this execution path.
  void refineType(
    Set<FlowSource> sources,
    ValueType type, {
    required bool negated,
  }) {
    if (sources.isEmpty) return;
    _mapValues(
      (value) => value.sources.any(sources.contains)
          ? value.check(type, negated: negated, runtimeTypes: true).value
          : value,
    );
  }

  void _mapValues(FlowValue Function(FlowValue) transform) {
    _globals = _globals.mapValues((_, slot) => slot.map(transform));
    _objects = _objects.mapValues((_, object) => object.map(transform));
    _regions = _regions.mapValues((_, region) => region.map(transform));
    _escaped = transform(_escaped);
    _externalAliases = transform(_externalAliases);
    _nativeContext = transform(_nativeContext);
  }

  /// Whether joining these native mappings would discard a known extent.
  bool losesNativeExtent(FlowState other) {
    if (identical(_regions, other._regions)) return false;
    for (final entry in _regions.differences(other._regions)) {
      final here = entry.after?.memory, there = entry.before?.memory;
      if (here != null && there != null && here.length != there.length) return true;
    }
    return false;
  }

  /// Adds an executable alternative, skipping unchanged storage subtrees.
  /// [widen] drops expanding numeric bounds at a loop or recursive boundary.
  bool join(FlowState incoming, {bool widen = false}) {
    if (!identical(program, incoming.program) ||
        !identical(memoryLayout, incoming.memoryLayout)) {
      throw ArgumentError(
        'Cannot join storage from a different graph or target layout.',
      );
    }
    final globals = _globals.merge(incoming._globals, (global, left, right) {
      final value = (left ?? _initial(global)).join(
        right ?? _initial(global),
        widen: widen,
      );
      return value == _initial(global) ? null : value;
    });
    final objects = incoming._objects.isEmpty
        ? _objects
        : _objects.isEmpty
        ? incoming._objects
        : _objects.merge(
            incoming._objects,
            (_, left, right) => left == null
                ? right!
                : right == null
                ? left
                : left.join(right, widen: widen),
          );
    final escaped = _escaped.join(incoming._escaped, widen: widen);
    final externalAliases = _externalAliases.join(
      incoming._externalAliases,
      widen: widen,
    );
    final nativeContext = _nativeContext.join(
      incoming._nativeContext,
      widen: widen,
    );
    final regions = _regions.merge(
      incoming._regions,
      (_, left, right) => left == null
          ? right
          : right == null
          ? left
          : left.join(
              right,
              widen: widen,
              nativeWords: left.summary || right.summary
                  ? null
                  : (isMappedAddress, incoming.isMappedAddress),
            ),
    );
    final addresses = _addresses.merge(
      incoming._addresses,
      (_, left, right) =>
          left == null || right == null ? null : left.join(right, widen: widen),
    );
    final writes = _writes.merge(
      incoming._writes,
      (_, left, right) => left == null
          ? right
          : right == null
          ? left
          : left.merge(right, (_, _, _) => true),
    );
    final changed =
        !identical(globals, _globals) ||
        !identical(objects, _objects) ||
        !identical(regions, _regions) ||
        !identical(addresses, _addresses) ||
        !identical(writes, _writes) ||
        nativeContext != _nativeContext ||
        escaped != _escaped ||
        externalAliases != _externalAliases;
    _globals = globals;
    _objects = objects;
    _regions = regions;
    _addresses = addresses;
    _escaped = escaped;
    _externalAliases = externalAliases;
    _nativeContext = nativeContext;
    _writes = writes;
    return changed;
  }

  _Slot _initial(GlobalVariable global) =>
      global.isInitiallyBound ? _Slot.bound(_null) : const _Slot.unbound();

  /// An immutable key for the current version, safe after this wrapper changes.
  Object get structuralKey => (
    program,
    memoryLayout,
    _globals,
    _objects,
    _regions,
    _addresses,
    _escaped,
    _externalAliases,
    _nativeContext,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FlowState && structuralKey == other.structuralKey;

  @override
  int get hashCode => structuralKey.hashCode;

  /// Local mappings that were never published on this exit cannot contribute
  /// bytes to a mapping published by a different return from the same call.
  FlowState returningMappings(FlowState entry, Iterable<FlowValue> roots) {
    if (identical(_regions, entry._regions)) return this;
    final fresh = [
      for (final region in _regions.keys)
        if (entry._regions[region] == null && region.site is DirectCall) region,
    ];
    if (fresh.isEmpty) return this;
    final visible = project([...entry.allocations, ...roots]);
    var regions = _regions;
    var writes = _writes;
    for (final region in fresh) {
      if (visible._regions[region] != null) continue;
      regions = regions.withoutKey(region);
      writes = writes.withoutKey(region);
    }
    return identical(regions, _regions)
        ? this
        : (copy()
            .._regions = regions
            .._writes = writes);
  }

  /// Projects a call input, or only storage proven observable by [access].
  /// Ordinary calls retain globals and external reachability.
  FlowState project(Iterable<FlowValue> roots, {FlowStorageAccess? access}) {
    // Without a proven address range, a raw write can cross allocation and
    // global boundaries. Keep the same state _invalidateRaw must invalidate;
    // restricting it to reachable objects would silently preserve stale facts.
    if (access?.rawWrites == true) return copy();
    final globals = access == null
        ? _globals
        : StateMap<GlobalVariable, _Slot>.fromEntries(
            _globals.entries.where(
              (entry) => access.globals.contains(entry.key),
            ),
          );
    final escaped = access == null || access.exposed
        ? _escaped
        : const FlowValue.bottom();
    final nativeContext = access == null || access.context
        ? _nativeContext
        : const FlowValue.bottom();
    final reachable = _reachable(
      [
        ...roots,
        nativeContext,
        if (access == null || access.memory)
          for (final target in _externalMemory.keys) externalResult(target)!,
        for (final data in access?.data ?? _nativeData.keys)
          if (access != null || _regions[_nativeData[data]!.allocation] != null)
            _dataAddress(data),
        for (final declaration in access?.modules ?? _moduleObjects.keys)
          if (access != null || _objects[_moduleObjects[declaration]!] != null)
            _moduleReference(declaration),
        escaped,
        for (final slot in globals.values) ...[slot.value, slot.initializer],
      ],
      expose: false,
      access: access,
      constants: false,
    );
    final externalAliases = reachable.externalUnknownTypes.isEmpty
        ? const FlowValue.bottom()
        : FlowValue.joined(_externalAliasObjects().map(FlowValue.object));
    var objects = const StateMap<FlowObject, _ObjectState>.empty();
    // Unknown writes use the same provenance boundary as capability traversal.
    for (final object in {
      ...reachable.objects,
      if (access?.writes == true)
        for (final object in _unknownAliases(reachable, memory: access!.memory))
          if (_readSlots(object, _objects[object]!, access).isNotEmpty) object,
    }) {
      if (_objects[object] case final state?) {
        objects = objects.withEntry(
          object,
          access == null
              ? state
              : _ObjectState._(
                  StateMap.fromEntries(_readSlots(object, state, access)),
                  access.memory ? state.captures : null,
                  state.summary,
                  access.memory || reachable.managedBackings.contains(object)
                      ? state.memory
                      : null,
                ),
        );
      }
    }
    final regions = StateMap<FlowObject, _ObjectState>.fromEntries([
      for (final address in reachable.addresses)
        if (address.base case FlowRegion(:final allocation))
          if (_regions[allocation] case final region?)
            MapEntry(allocation, region),
    ]);
    var writes = const StateMap<Object, StateMap<Object, bool>>.empty();
    for (final entry in _writes.entries) {
      if (entry.key case final FlowObject object) {
        if (objects[object] != null || regions[object] != null) {
          writes = writes.withEntry(object, entry.value);
        }
      } else {
        final slots = access == null
            ? entry.value
            : StateMap<Object, bool>.fromEntries(
                entry.value.entries.where(
                  (slot) => access.globals.contains(slot.key),
                ),
              );
        if (!slots.isEmpty) writes = writes.withEntry(entry.key, slots);
      }
    }
    return FlowState._(
      program,
      memoryLayout,
      _externalMemory,
      _nativeData,
      _moduleObjects,
      _declaredGlobals,
      _classes,
      _constantMemory,
      globals,
      objects,
      regions,
      StateMap.fromEntries(
        _addresses.entries.where(
          (entry) => entry.value.addresses.every(
            (address) =>
                address.base is FlowRegion ||
                address.base is FlowObject &&
                    objects[address.base as FlowObject] != null,
          ),
        ),
      ),
      escaped,
      externalAliases,
      nativeContext,
      writes,
    );
  }

  /// Applies an exit relative to the entry snapshot that produced its summary.
  ///
  /// Writes are tracked independently of value equality. Untouched caller slots
  /// retain their values while gaining equalities established by callee reads.
  /// The entry must start with `copy(resetWrites: true)` before execution.
  FlowState applySummary(
    FlowState before,
    FlowState after, {
    required FlowObject Function(FlowObject) mapObject,
    required FlowValue Function(FlowValue) mapValue,
  }) {
    if (!before._writes.isEmpty) {
      throw ArgumentError('A summary entry must exclude caller write history.');
    }
    if (!identical(program, before.program) ||
        !identical(program, after.program) ||
        !identical(memoryLayout, before.memoryLayout) ||
        !identical(memoryLayout, after.memoryLayout)) {
      throw ArgumentError(
        'A call summary belongs to one graph and target layout.',
      );
    }
    final result = copy();
    _Slot preserve(_Slot next, _Slot? previous, bool written) {
      if (written || previous == null) return next;
      return _Slot._(
        previous.value.withSources({
          ...next.value.sources,
          ...previous.value.sources,
        }),
        previous.unbound,
        previous.initializer.withSources({
          ...next.initializer.sources,
          ...previous.initializer.sources,
        }),
        previous.rawOverwrite,
      );
    }

    for (final global in {
      for (final change in after._globals.differences(before._globals))
        change.key,
      ...?after._writes[_globalWrites]?.keys.cast<GlobalVariable>(),
    }) {
      result._setGlobal(
        global,
        preserve(
          (after._globals[global] ?? _initial(global)).map(mapValue),
          result._globals[global] ?? result._initial(global),
          after._written(null, global),
        ),
      );
    }
    for (final identity in {
      for (final change in after._objects.differences(before._objects))
        change.key,
      ...after._writes.keys.whereType<FlowObject>(),
    }) {
      final next = after._objects[identity];
      if (next == null) continue; // Projection is not an object destruction.
      final object = mapObject(identity);
      final prior = before._objects[identity];
      var current = result._objects[object];
      if (prior == null || current == null) {
        result._allocate(object, next.map(mapValue));
        continue;
      }
      var fieldsChanged = false;
      for (final key in {
        for (final slot in next.slots.differences(prior.slots)) slot.key,
        for (final key in after._writes[identity]?.keys ?? const <Object>[])
          if (key is InstanceField || identical(key, _cell)) key,
      }) {
        final slot = next.slots[key];
        if (slot == null) {
          throw StateError('A summary cannot remove a declared storage slot.');
        }
        final written = after._written(identity, key);
        fieldsChanged |= written && key is InstanceField;
        current = current!.withSlot(
          key,
          preserve(slot.map(mapValue), current.slots[key], written),
        );
      }
      current = current!.withFlags(summary: next.summary && !prior.summary);
      if (after._written(identity, _captureWrites)) {
        current = _ObjectState._(
          current.slots,
          next.captures == null
              ? null
              : List.unmodifiable(next.captures!.map(mapValue)),
          current.summary,
          current.memory,
        );
      }
      if (after._written(identity, _objectMemoryWrites)) {
        current = current.withMemory(next.memory?.map(mapValue));
      }
      result._objects = result._objects.withEntry(object, current);
      if (fieldsChanged && next.memory == null) {
        result._forgetFieldBytes(object);
      }
    }
    if (after._escaped != before._escaped) {
      result._escaped = result._escaped.join(mapValue(after._escaped));
    }
    if (after._externalAliases != before._externalAliases) {
      result._externalAliases = result._externalAliases.join(
        mapValue(after._externalAliases),
      );
    }
    final absentInputs = <FlowObject>{};
    final changedRegions = <FlowObject, _ObjectState>{};
    for (final identity in {
      for (final change in after._regions.differences(before._regions))
        change.key,
      for (final key in after._writes.keys.whereType<FlowObject>())
        if (after._written(key, _regionWrites)) key,
    }) {
      final region = after._regions[identity];
      if (region == null) continue;
      final prior = before._regions[identity];
      if (prior != null && !after._written(identity, _regionWrites)) continue;
      final owner = mapObject(identity);
      var exit = region.map(mapValue);
      // A fresh mapping is unique inside the invocation. Its bounded name in
      // the caller may also denote a mapping returned by an earlier call.
      final occupied = _regions[owner];
      // This summary may include inputs supplied by a different caller.
      // A write to its old mapping cannot affect a fresh allocation in this
      // caller merely because both map to the same bounded result identity.
      if (prior != null &&
          occupied == null &&
          identity.site is DirectCall &&
          !_externalMemory.containsKey((identity.site as DirectCall).target) &&
          !after._written(identity, _mappedRegions)) {
        absentInputs.add(identity);
        continue;
      }
      if (prior == null && occupied != null) {
        exit = occupied.join(exit).withFlags(summary: true);
      } else if (occupied != null &&
          prior != null &&
          (occupied.summary || occupied != prior.map(mapValue))) {
        exit = occupied.join(exit);
      }
      if (changedRegions[owner] case final other?) {
        exit = other.join(exit).withFlags(summary: true);
      }
      changedRegions[owner] = exit;
    }
    for (final entry in changedRegions.entries) {
      result._regions = result._regions.withEntry(entry.key, entry.value);
    }
    for (final change in after._addresses.differences(before._addresses)) {
      if (change.after case final address?) {
        final sources = mapValue(
          FlowValue.unknown(.integer).withSources([change.key]),
        ).sources;
        for (final source in sources) {
          result._addresses = result._addresses.withEntry(
            source,
            mapValue(address),
          );
        }
      }
    }
    for (final owner in after._writes.entries) {
      if (absentInputs.contains(owner.key)) continue;
      final mapped = owner.key is FlowObject
          ? mapObject(owner.key as FlowObject)
          : owner.key;
      for (final key in owner.value.keys) {
        result._recordWrite(
          mapped == _globalWrites ? null : mapped as FlowObject,
          key,
        );
      }
    }
    return result;
  }

  bool _written(FlowObject? object, Object key) =>
      _writes[object ?? _globalWrites]?[key] == true;

  /// Whether this exit preserves every concrete location used by a source read.
  /// This tests semantic writes, including writes whose abstract value is equal.
  bool preservesRead(Instruction read, List<FlowValue> operands) {
    if (read case LoadGlobal(:final global)) return !_written(null, global);
    final key = switch (read) {
      LoadField(:final field) => field,
      ReadCell() => _cell,
      _ => null,
    };
    if (key == null || operands.length != 1) return false;
    final receiver = operands.single;
    return receiver.objects.isNotEmpty &&
        receiver.constants.isEmpty &&
        receiver.unknownTypes.isEmpty &&
        receiver.addresses.isEmpty &&
        receiver.objects.every((object) => !_written(object, key));
  }

  void _recordWrite(FlowObject? object, Object key) {
    final owner = object ?? _globalWrites;
    _writes = _writes.withEntry(
      owner,
      (_writes[owner] ?? const StateMap<Object, bool>.empty()).withEntry(
        key,
        true,
      ),
    );
  }

  void _setGlobal(GlobalVariable global, _Slot slot) {
    _globals = slot == _initial(global)
        ? _globals.withoutKey(global)
        : _globals.withEntry(global, slot);
  }

  /// Whether this state contains storage for the analysis allocation.
  bool containsObject(FlowObject object) =>
      _objects[object] != null || _regions[object] != null;

  /// Identities carried by entry values and storage, independently of contents.
  Set<FlowObject> allocationIdentities(Iterable<FlowValue> roots) {
    final reachable = _reachable(
      [
        ...roots,
        ...allocations,
        _nativeContext,
        _escaped,
        _externalAliases,
        for (final slot in _globals.values) ...[slot.value, slot.initializer],
        ..._addresses.values,
      ],
      expose: false,
      constants: false,
    );
    return {
      ...reachable.objects,
      for (final address in reachable.addresses)
        if (address.base case FlowRegion(:final allocation)) allocation,
    };
  }

  /// Whether this state holds a single allocation for the supplied identity.
  bool hasSingletonAllocation(Object identity) => switch (identity) {
    FlowObject() => _objects[identity]?.summary == false,
    FlowRegion(:final allocation) => _regions[allocation]?.summary == false,
    _ => false,
  };

  /// Allocation identities whose state can be changed by an invocation.
  Iterable<FlowObject> get objects => _objects.keys;

  /// Storage held by an incoming caller, including native mappings.
  Iterable<FlowValue> get allocations => [
    ..._objects.keys.map(FlowValue.object),
    for (final region in _regions.keys)
      FlowValue.address(FlowAddress(FlowRegion(region), 0)),
  ];

  /// Records a native mapping without treating its address as a managed root.
  FlowResult allocateMemory(
    FlowObject region,
    FlowValue byteLength, {
    required bool repeated,
  }) {
    final next = copy();
    final size = byteLength.integers?.constant;
    final storage = _ObjectState(
      {},
      memory: FlowMemory(0, size != null && size > 0 ? size : null),
      summary: repeated,
    );
    final previous = next._regions[region];
    next._recordWrite(region, _mappedRegions);
    next._recordWrite(region, _regionWrites);
    next._regions = next._regions.withEntry(
      region,
      previous == null
          ? storage
          : previous.join(storage).withFlags(summary: true),
    );
    return _normal(
      FlowValue.address(FlowAddress(FlowRegion(region), 0))
          .join(FlowValue.constant(const Constant.integer(0))),
      next,
    );
  }

  /// Captures of this allocation, preserving shared cell identities.
  List<FlowValue>? capturesOf(FlowObject object) {
    if (object.callableStorage case final storage?) {
      final slots = [
        if (storage.origin case final origin?) origin else ...storage.captures,
      ];
      final values = slots
          .map((field) => storedFieldOf(object, field))
          .toList();
      return values.any((value) => value == null)
          ? null
          : values.cast<FlowValue>();
    }
    return _objects[object]?.captures;
  }

  /// Reads a bound physical slot without inventing an unknown initializer value.
  FlowValue? storedFieldOf(FlowObject object, InstanceField field) {
    if (object.storageType?.asInstanceOf(field.owner) == null) {
      throw ArgumentError('Field does not belong to the allocation layout.');
    }
    final slot = _objects[object]?.slots[field];
    return slot == null || slot.unbound ? null : resolveValue(slot.value);
  }

  /// The descriptor actually written to this function's shared object header.
  FlowValue? callableRuntimeTypeOf(FlowObject object) =>
      object.callableStorage == null
      ? null
      : _objects[object]?.memory?.readReference(ObjectHeader.typeOffset);

  /// Records the environment of a closure selected by the program solver.
  void retain(
    FlowObject object,
    List<FlowValue> captures, {
    required bool repeated,
  }) {
    _allocate(object, _ObjectState({}, captures: captures, summary: repeated));
  }

  /// GC reachability, including environments hidden behind callable values.
  FlowValue get escapedValues => reachableValues([_escaped]);

  /// Values unknown code may access independently of calling a closure.
  FlowValue get exposedValues => exposedFrom([_escaped]);

  /// Storage roots a Dart invocation can access without explicit arguments.
  ///
  /// Includes lowered module objects, writable native module data and the
  /// inherited native context. These are values, not additional entry points.
  FlowValue get programValues => FlowValue.joined([
    _nativeContext,
    for (final slot in _globals.values) ...[slot.value, slot.initializer],
    for (final object in _moduleObjects.values)
      if (_objects[object] != null) FlowValue.object(object),
    for (final entry in _nativeData.entries)
      if (entry.key.writable && _regions[entry.value.allocation] != null)
        FlowValue.address(FlowAddress(FlowRegion(entry.value.allocation), 0)),
  ]);

  /// Records capabilities crossing a boundary, including values already read there.
  FlowValue escape(Iterable<FlowValue> roots) {
    for (final root in roots) {
      _escaped = _escaped.join(root);
    }
    // Outside code may retain a field value even after its owner overwrites it.
    _escaped = _escaped.join(exposedValues);
    return escapedValues;
  }

  /// Forgets values an external operation can write through the given roots.
  ///
  /// The caller supplies previously escaped roots and program-wide access
  /// explicitly. [globals] includes globals after lowering to module storage.
  void invalidate(
    Iterable<FlowValue> roots, {
    bool globals = false,
    FlowValue writtenReferences = const FlowValue.bottom(),
  }) {
    final reachable = exposedFrom([...roots, if (globals) programValues]);
    // A program slot may itself hold a raw capability. It has the same write
    // authority as that capability supplied directly as an argument.
    final raw = reachableValues([reachable.references]);
    for (final object in raw.objects) {
      if (object.storageView != null) {
        _recordRawSlotWrites(FlowValue.address(FlowAddress.ranged(object, null)), null);
      }
    }
    for (final object in reachable.objects) {
      final state = _objects[object];
      if (state == null) continue;
      var next = state;
      for (final entry in state.slots.entries) {
        final key = entry.key;
        final type = key is InstanceField
            ? key.typeFor(object.storageType!)
            : (object.type as CellType).content;
        final isFinal = key is InstanceField
            ? key.isFinal
            : (object.type as CellType).isFinal;
        final readonly = isFinal && !raw.objects.contains(object);
        if (entry.value.permitsWrite(readonly)) {
          _recordWrite(object, key);
        }
        next = next.withSlot(
          key,
          entry.value.invalidate(type, isFinal: readonly),
        );
      }
      next = next.withMemory(
        state.memory?.invalidate().retainReferences(writtenReferences),
      );
      if (state.memory != null) _recordWrite(object, _objectMemoryWrites);
      _objects = _objects.withEntry(object, next);
    }
    for (final address in reachable.addresses) {
      if (address.base case FlowRegion(:final allocation)) {
        final region = _regions[allocation];
        if (region != null) {
          _recordWrite(allocation, _regionWrites);
          _regions = _regions.withEntry(
            allocation,
            region.withMemory(
              region.memory!.invalidate().retainReferences(writtenReferences),
            ),
          );
        }
      }
    }
    if (globals) {
      for (final global in _declaredGlobals) {
        final slot = _globals[global] ?? _initial(global);
        if (slot.permitsWrite(global.isFinal)) _recordWrite(null, global);
        _setGlobal(
          global,
          slot.invalidate(global.type, isFinal: global.isFinal),
        );
      }
    }
  }

  /// Installs zeroed field and inline storage after the managed allocator returned.
  void acceptManagedAllocation(FlowObject object, FlowValue bytes, {required bool repeated}) {
    final fixed = memoryLayout?.objectLayout(object.storageType!).size;
    final size = bytes.integers?.constant;
    final extent = fixed != null && size != null && size >= 0 &&
            size <= 0x7fffffffffffffff - fixed ? fixed + size : fixed;
    _allocate(object, _ObjectState(_initialFields(object.storageType!),
        summary: repeated, memory: FlowMemory(0, extent ?? ObjectHeader.fieldsOffset)
            .forget(0, ObjectHeader.fieldsOffset)));
  }

  /// Allocates one source instance and runs its generative initializer.
  ///
  /// Direct construction and constructor-valued calls share these state rules.
  FlowResult construct(
    FlowObject object,
    FunctionTarget initializer,
    List<FlowValue> arguments, {
    required bool repeated,
    required FlowInvoke invoke,
    FlowValue? typeDescriptor,
  }) {
    if (arguments.any((value) => value.isBottom)) return _unreachable;
    final next = copy();
    next._allocate(
      object,
      _ObjectState(
        _initialFields(object.storageType!),
        summary: repeated,
        memory: typeDescriptor == null
            ? null
            : FlowMemory(
                    0,
                    memoryLayout?.objectLayout(object.storageType!).size ??
                        ObjectHeader.fieldsOffset,
                  )
                  .forget(0, ObjectHeader.fieldsOffset)
                  .writeReference(ObjectHeader.typeOffset, typeDescriptor),
      ),
    );
    final value = FlowValue.object(object);
    final result = invoke(initializer, [value, ...arguments], next);
    return FlowResult(
      value: result.normal == null ? const .bottom() : value,
      normal: result.normal,
      exceptional: result.exceptional,
      allocationFailureOnly: result.allocationFailureOnly,
      exception: result.exception,
      stackTrace: result.stackTrace,
      effects: const {Effect.allocates},
    );
  }

  Map<Object, _Slot> _initialFields(ClassType type) {
    final slots = <Object, _Slot>{};
    for (ClassType? view = type; view != null; view = view.superclass) {
      for (final field in _class(view)?.fields ?? <InstanceField>[]) {
        slots[field] = !field.initiallyUnbound && !field.isLate && field.typeFor(type).mayBeNull
            ? _Slot.bound(_null)
            : const _Slot.unbound();
      }
    }
    return slots;
  }

  /// Evaluates storage operations; null leaves other operations to the solver.
  /// [resultType] is the caller-substituted type for the current activation.
  FlowResult? transfer(
    Instruction operation,
    List<FlowValue> operands, {
    required FlowObject Function(Instruction) allocate,
    required bool repeated,
    required FlowInvoke invoke,
    required FlowCall call,
    ValueType? resultType,
  }) {
    resultType ??= operation.type;
    if (operands.length != operation.inputs.length) {
      throw ArgumentError('Storage transfer requires every operand.');
    }
    operands = operands.map(resolveValue).toList();
    switch (operation) {
      case ReadNativeContext():
        return _withEffects(_normal(_nativeContext, copy()), const {
          Effect.readsStorage,
        });
      case BindNativeContext():
        if (operands.single.isBottom) return _unreachable;
        return _withEffects(
          _normal(_null, copy(nativeContext: operands.single)),
          const {Effect.writesStorage},
        );
      case NativeDataAddress(:final declaration):
        return _normal(_dataAddress(declaration), copy());
      case ModuleObjectReference(:final declaration):
        return _normal(_moduleReference(declaration), copy());
      case ModuleRootsAddress():
        return _normal(
          FlowValue.address(FlowAddress(FlowMetadata.moduleRoots, 0))
              .withReferences(_moduleObjects.keys.map(_moduleReference)),
          copy(),
        );
      case NativeLocalStorage(
        :final declaration,
        :final storage,
        :final zeroInitialize,
      ):
        final region = allocate(declaration);
        final previous = _regions[region];
        final size = memoryLayout?.nativeLayout.of(storage).size;
        final initialized = FlowMemory(0, size);
        final memory = zeroInitialize
            ? previous != null && (repeated || previous.summary)
                  ? previous.memory!.join(initialized)
                  : initialized
            : previous?.memory ?? initialized.invalidate();
        final next = copy();
        if (previous == null || zeroInitialize) {
          next._recordWrite(region, _regionWrites);
        }
        next._regions = next._regions.withEntry(
          region,
          previous == null
              ? _ObjectState({}, memory: memory, summary: repeated)
              : previous.withMemory(memory).withFlags(summary: repeated),
        );
        return _withEffects(
          _normal(FlowValue.address(FlowAddress(FlowRegion(region), 0)), next),
          zeroInitialize ? const {Effect.writesStorage} : const {},
        );
      case MaterializeValue():
        if (operands.single.isBottom) return _unreachable;
        final storage = ExecutionShapes.scalarStorageOf(resultType);
        final type = FfiTypes.valueType(storage) as ClassType;
        final allocation = allocate(operation);
        final backing = FlowObject(allocation.site, allocation.activation,
            type: type, variant: allocation.variant);
        final layout = memoryLayout;
        final payload = operands.single.withManagedBackings(const []);
        final next = copy().._allocate(backing, _ObjectState(
          _initialFields(type), summary: repeated,
          memory: layout == null ? null : FlowMemory(
              0, layout.objectLayout(type).size)
              .forget(0, ObjectHeader.fieldsOffset)
              .write(ObjectHeader.fieldsOffset, storage, payload,
                  layout.nativeLayout),
        ));
        return _withEffects(_normal(payload.withSources(const [])
            .withManagedBackings([backing]), next), const {Effect.allocates});
      case ProjectValue():
        if (operands.single.isBottom) return _unreachable;
        final source = operands.single;
        if (source.constant != null && source.managedBackings.isEmpty &&
            !source.hasUnknownBacking) {
          return _normal(source, copy());
        }
        final projected = _readNative(_objectAddress(source,
            FlowValue.constant(const Constant.integer(ObjectHeader.fieldsOffset))),
            ExecutionShapes.scalarStorageOf(resultType), resultType);
        return FlowResult(
          value: projected.value.withManagedBackings(const []),
          normal: projected.normal, exceptional: projected.exceptional,
          exception: projected.exception, stackTrace: projected.stackTrace,
          effects: projected.effects,
        );
      case AllocatedObject():
        if (operands.any((value) => value.isBottom)) return _unreachable;
        final next = copy();
        var value = const FlowValue.bottom();
        final address = operands.first;
        var fresh =
            address.addresses.isEmpty ||
            address.unknownTypes.isNotEmpty ||
            address.constants.isNotEmpty ||
            address.objects.isNotEmpty;
        for (final pointer in address.addresses) {
          if (pointer.base case final FlowObject object
              when pointer.offset == 0 &&
                  object.type == resultType &&
                  containsObject(object)) {
            value = value.join(FlowValue.object(object));
          } else {
            fresh = true;
          }
        }
        if (fresh) {
          final object = allocate(operation);
          final size = operands.last.integers?.constant;
          final fixed = memoryLayout?.objectLayout(object.storageType!).size;
          final extent = fixed == null
              ? ObjectHeader.fieldsOffset
              : size != null && size >= 0 && size <= 0x7fffffffffffffff - fixed
              ? fixed + size
              : fixed;
          next._allocate(
            object,
            _ObjectState(
              _initialFields(object.storageType!),
              summary: repeated,
              memory: FlowMemory(
                0,
                extent,
              ).forget(0, ObjectHeader.fieldsOffset),
            ),
          );
          value = value.join(FlowValue.object(object));
        }
        final known = next._objectAddress(
          value,
          FlowValue.constant(const Constant.integer(0)),
        );
        for (final source in address.sources) {
          next._addresses = next._addresses.withEntry(source, known);
        }
        return _normal(value, next);
      case ObjectDescriptorAddress(:final declaration):
        return _normal(FlowValue.address(FlowAddress(declaration, 0)), copy());
      case NativeSize() || NativeFieldOffset():
        final layout = memoryLayout?.nativeLayout;
        if (layout == null) return null;
        final value = switch (operation) {
          NativeSize(:final nativeType) => layout.of(nativeType).size,
          NativeFieldOffset(:final owner, :final index) =>
            layout.of(owner).offsets[index],
          _ => throw StateError('Expected a native layout query.'),
        };
        return _normal(FlowValue.constant(Constant.integer(value)), copy());
      case NewPayload():
        if (operands.single.isBottom) return _unreachable;
        final object = allocate(operation);
        final size = operands.single.constant;
        final length = size is ScalarConstant && size.value is int
            ? size.value as int
            : null;
        final fixedSize = memoryLayout?.objectLayout(object.storageType!).size;
        final valid =
            length != null &&
            length >= 0 &&
            (fixedSize == null || length <= 0x7fffffffffffffff - fixedSize);
        final next = copy()
          .._allocate(
            object,
            _ObjectState(
              _initialFields(object.storageType!),
              summary: repeated,
              memory: fixedSize == null
                  ? null
                  : FlowMemory(
                      ObjectHeader.fieldsOffset,
                      valid
                          ? fixedSize - ObjectHeader.fieldsOffset + length
                          : null,
                    ),
            ),
          );
        return FlowResult(
          value: .object(object),
          normal: next,
          exceptional: valid ? null : copy(),
          effects: const {Effect.allocates},
        );
      case LoadObjectReference():
        if (operands.any((value) => value.isBottom)) return _unreachable;
        final value =
            _readReference(operands.first, operands[1]) ??
            FlowValue.unknown(.object.nullable).withReferences([
              reachableValues([operands.first]),
            ]);
        return _withEffects(_normal(value, copy()), const {
          Effect.readsStorage,
        });
      case StoreObjectReference():
        if (operands.any((value) => value.isBottom)) return _unreachable;
        final range = _nativeWriteRange(operation, operands);
        final next = _writeNative(
          range.address,
          range.size,
          operands.last,
          (memory, offset) => memory.writeReference(offset, operands.last),
          writeWidth: ObjectHeader.alignment,
        );
        return _withEffects(_normal(_null, next), const {Effect.writesStorage});
      case LoadNative(nativeType: final NativeTypeRef nativeType) ||
          LoadObjectData(nativeType: final NativeTypeRef nativeType):
        if (operands.any((value) => value.isBottom)) return _unreachable;
        final input = operation is LoadObjectData
            ? _objectAddress(operands.first, operands.last)
            : operands.single;
        return _readNative(input, nativeType, resultType);
      case StringLength():
        if (operands.single.isBottom) return _unreachable;
        final layout = memoryLayout?.objectLayout(ValueType.string);
        if (layout == null) return null;
        return _readNative(
          _objectAddress(
            operands.single,
            FlowValue.constant(Constant.integer(layout.offsetOf(0))),
          ),
          NativeScalarType(Int64),
          resultType,
        );
      case StoreNative(nativeType: final NativeTypeRef nativeType) ||
          StoreObjectData(nativeType: final NativeTypeRef nativeType):
        if (operands.any((v) => v.isBottom)) return _unreachable;
        final range = _nativeWriteRange(operation, operands);
        final layout = memoryLayout?.nativeLayout;
        final next = _writeNative(
          range.address,
          range.size,
          operands.last,
          (memory, offset) =>
              memory.write(offset, nativeType, operands.last, layout!),
        );
        return _withEffects(_normal(_null, next), const {Effect.writesStorage});
      case CopyNative():
        if (operands.any((v) => v.isBottom)) return _unreachable;
        final range = _nativeWriteRange(operation, operands);
        final size = range.size;
        if (size == 0) return _normal(_null, copy());
        final source = operands.last;
        final sourceReferences = reachableValues([source]);
        final next = _writeNative(range.address, size, sourceReferences, (
          memory,
          offset,
        ) {
          FlowMemory? result;
          for (final address in source.addresses) {
            final from = _memoryOf(address.base);
            var copied = from != null && address.offset != null
                ? memory.copyFrom(offset, from, address.offset!, size!)
                : memory.forget(offset, size!, retained: sourceReferences);
            if (from != null &&
                address.offsets != null &&
                !from.hasCompleteRead(address.offsets!, size)) {
              copied = copied.retainReferences(sourceReferences);
            }
            result = result == null ? copied : result.join(copied);
          }
          if (result == null ||
              source.unknownTypes.isNotEmpty ||
              source.constants.isNotEmpty) {
            result = memory.forget(offset, size!, retained: sourceReferences);
          }
          return result;
        });
        return _withEffects(_normal(_null, next), const {
          Effect.readsStorage,
          Effect.writesStorage,
        });
      case Construct(:final initializer, :final callableStorage):
        return construct(
          allocate(operation),
          initializer,
          callableStorage == null
              ? operands
              : operands.take(operands.length - 1).toList(),
          repeated: repeated,
          invoke: invoke,
          typeDescriptor: callableStorage == null ? null : operands.last,
        );
      case NewCell(:final initial, :final initializer):
        if (operands.any((value) => value.isBottom)) return _unreachable;
        final object = allocate(operation);
        final checked = initial == null
            ? (value: const FlowValue.bottom(), mayFail: false)
            : (object.type as CellType).isLate
            ? operands.first.check((object.type as CellType).content)
            : (value: operands.first, mayFail: false);
        if (initial != null && checked.value.isBottom) {
          return FlowResult(
            value: const .bottom(),
            normal: null,
            exceptional: copy(),
            exception: _typeError,
          );
        }
        final slot = initial != null
            ? _Slot.bound(checked.value)
            : _Slot.unbound(
                initializer: initializer == null
                    ? const .bottom()
                    : operands.single,
              );
        final next = copy();
        next._allocate(object, _ObjectState({_cell: slot}, summary: repeated));
        return FlowResult(
          value: .object(object),
          normal: next,
          exceptional: checked.mayFail ? copy() : null,
          exception: _typeError,
          effects: const {Effect.allocates},
        );
      case CopyCell():
        if (operands.single.isBottom) return _unreachable;
        final object = allocate(operation);
        _Slot? copied;
        for (final source in operands.single.objects) {
          final slot =
              _objects[source]?.slots[_cell] ??
              _Slot.unknown((source.type as CellType).content);
          copied = copied == null ? slot : copied.join(slot);
        }
        if (operands.single.unknownTypes.isNotEmpty) {
          final slot = _Slot.unknown((object.type as CellType).content);
          copied = copied == null ? slot : copied.join(slot);
        }
        if (copied == null) return _unreachable;
        final next = copy();
        next._allocate(
          object,
          _ObjectState({_cell: copied}, summary: repeated),
        );
        return _withEffects(_normal(.object(object), next), const {
          Effect.readsStorage,
          Effect.allocates,
        });
      case MakeClosure():
        if (operands.any((value) => value.isBottom)) return _unreachable;
        final object = allocate(operation);
        final next = copy()..retain(object, operands, repeated: repeated);
        return _withEffects(_normal(.object(object), next), const {
          Effect.allocates,
        });
      case LoadGlobal(:final global):
        _requireGlobal(global);
        return _read(
          (null, global),
          global.type,
          isFinal: global.isFinal,
          initialize: global.initializer == null
              ? null
              : (input) => invoke(global.initializer!, [], input),
        );
      case StoreGlobal(:final global):
        _requireGlobal(global);
        return _write(
          (null, global),
          operands.single,
          global.type,
          isFinal: global.isFinal,
        );
      case ReadCell():
        return _readObjects(
          operands.single,
          _cell,
          resultType,
          invoke: invoke,
          call: call,
        );
      case LoadField(:final field):
        return _readObjects(
          operands.single,
          field,
          resultType,
          invoke: invoke,
          call: call,
        );
      case WriteCell():
        return _writeObjects(operands.first, _cell, operands.last);
      case InitializeStorageField(:final field):
        return _copyFieldSlot(field, operands.first, operands.last);
      case StoreField(:final field):
        final written = _writeObjects(operands.first, field, operands.last);
        return FlowResult(
          value: written.normal == null ? const FlowValue.bottom() : _null,
          normal: written.normal,
          exceptional: written.exceptional,
          exception: written.exception,
          stackTrace: written.stackTrace,
          effects: written.effects,
        );
      default:
        return null;
    }
  }

  Iterable<Object> _physicalBases(FlowValue owner) {
    final carrier = owner.carrierReferences;
    return <Object>[...carrier.objects, ...carrier.constants];
  }

  bool _unknownPhysicalBase(FlowValue owner) =>
      owner.carrierReferences.unknownTypes.isNotEmpty;

  FlowValue _objectAddress(FlowValue owner, FlowValue offset) {
    var value = const FlowValue.bottom();
    for (final base in _physicalBases(owner)) {
      value = value.join(
        FlowValue.address(FlowAddress.ranged(base, offset.integers)),
      );
    }
    if (_unknownPhysicalBase(owner) || value.isBottom) {
      value = value.join(FlowValue.unknown(.integer).withReferences([owner]));
    }
    return value;
  }

  FlowMemory? _memoryOf(Object base) {
    if (base is FlowObject) return _objects[base]?.memory;
    if (base is FlowRegion) return _regions[base.allocation]?.memory;
    if (base == FlowMetadata.moduleRoots && memoryLayout != null) {
      return _constantMemory.putIfAbsent(base, () {
        final count = _moduleObjects.length;
        final layout = memoryLayout!.nativeLayout;
        final word = NativeScalarType(Int64);
        var memory =
            FlowMemory(
              0,
              ModuleRootTable.entries + count * ModuleRootTable.entrySize,
            ).write(
              ModuleRootTable.count,
              word,
              FlowValue.unknown(.integer)
                  .restrictIntegers(FlowIntegerRange(0, count)),
              layout,
            );
        // Selection may delete declarations or change their order. Preserve
        // real object identities without folding a provisional table index.
        final candidates = FlowValue.joined([
          for (final object in _moduleObjects.values)
            FlowValue.address(FlowAddress(object, 0)),
        ]);
        for (var index = 0; index < count; index++) {
          memory = memory.write(
            ModuleRootTable.entries + index * ModuleRootTable.entrySize,
            word,
            candidates,
            layout,
          );
        }
        return memory;
      });
    }
    if (base is ClassType && memoryLayout != null) {
      return _constantMemory.putIfAbsent(base, () {
        final words = memoryLayout!.objectLayout(base).descriptorWords;
        var memory = FlowMemory(
          0,
          words.length * ObjectHeader.alignment,
        ).invalidate();
        for (final (index, word) in words.indexed) {
          if (word == null) continue;
          memory = memory.write(
            index * ObjectHeader.alignment,
            NativeScalarType(Int64),
            FlowValue.constant(Constant.integer(word)),
            memoryLayout!.nativeLayout,
          );
        }
        return memory;
      });
    }
    if (base case ScalarConstant(value: final String text)
        when memoryLayout != null) {
      return _constantMemory.putIfAbsent(base.structuralKey, () {
        final layout = memoryLayout!.objectLayout(ValueType.string);
        final start = layout.size;
        var memory =
            FlowMemory(
              ObjectHeader.fieldsOffset,
              start - ObjectHeader.fieldsOffset + text.length * 2,
            ).invalidate().write(
              layout.offsetOf(0),
              NativeScalarType(Int64),
              FlowValue.constant(Constant.integer(text.length)),
              memoryLayout!.nativeLayout,
            );
        final unit = NativeScalarType(Uint16);
        for (var index = 0; index < text.length; index++) {
          memory = memory.write(
            start + index * 2,
            unit,
            FlowValue.constant(Constant.integer(text.codeUnitAt(index))),
            memoryLayout!.nativeLayout,
          );
        }
        return memory;
      });
    }
    if (base is! ObjectConstant ||
        base.payload.isEmpty ||
        memoryLayout == null) {
      return null;
    }
    final layout = memoryLayout!.objectLayout(base.type as ClassType);
    if (!layout.tracesPayload) return null;
    return _constantMemory.putIfAbsent(base.structuralKey, () {
      var memory = FlowMemory(
        layout.size,
        base.payload.length * ObjectHeader.alignment,
      );
      for (final (index, value) in base.payload.indexed) {
        memory = memory.writeReference(
          layout.size + index * ObjectHeader.alignment,
          FlowValue.constant(value),
        );
      }
      return memory;
    });
  }

  bool _referenceSlot(FlowValue owner, FlowValue offset) {
    final offsets = offset.integers;
    final bases = _physicalBases(owner).toList();
    if (bases.isEmpty || _unknownPhysicalBase(owner) || offsets == null) {
      return false;
    }
    return offsets.zeroBits >= ObjectHeader.alignment.bitLength - 1 &&
        bases.every((base) {
          final type = switch (base) {
            FlowObject(:final type) || ObjectConstant(:final type) => type,
            _ => null,
          };
          final layout = type is ClassType
              ? memoryLayout?.objectLayout(type)
              : null;
          return (offsets.constant == ObjectHeader.typeOffset ||
                  layout != null &&
                      layout.tracesPayload &&
                      offsets.lower >= layout.size) &&
              (_memoryOf(base)
                      ?.containsRange(offsets, ObjectHeader.alignment) ??
                  false);
        });
  }

  FlowValue? _readReference(FlowValue owner, FlowValue offset) {
    if (!_referenceSlot(owner, offset)) return null;
    var value = const FlowValue.bottom();
    for (final base in _physicalBases(owner)) {
      final read = _memoryOf(base)!.readReferenceRange(offset.integers!);
      if (read == null) return null;
      value = value.join(resolveValue(read));
    }
    return value;
  }

  FlowResult _readNative(
    FlowValue input,
    NativeTypeRef nativeType,
    ValueType resultType,
  ) {
    var value = const FlowValue.bottom();
    final layout = memoryLayout?.nativeLayout;
    final size = layout?.of(nativeType).size;
    for (final address in input.addresses) {
      final memory = _memoryOf(address.base);
      final bounded =
          layout != null &&
          size != null &&
          address.offsets != null &&
          memory != null &&
          memory.containsRange(address.offsets!, size);
      var read = bounded
          ? memory.readRange(address.offsets!, nativeType, layout)
          : FlowValue.unknown(resultType);
      // Missing bytes require capabilities at the read, not at a later escape.
      // The byte model owns this proof for both Dart and native storage.
      if (!bounded || !memory.hasCompleteRead(address.offsets!, size)) {
        read = read.withReferences([
          reachableValues([address.reference, input.references]),
        ]);
      }
      value = value.join(read);
    }
    if (input.addresses.isEmpty ||
        input.objects.isNotEmpty ||
        input.unknownTypes.isNotEmpty ||
        input.constants.isNotEmpty) {
      value = value.join(
        FlowValue.unknown(resultType).withReferences([
          reachableValues([input.references]),
        ]),
      );
    }
    return _withEffects(_normal(value, copy()), const {Effect.readsStorage});
  }

  /// Whether every native access stays within modeled object storage.
  /// Constants may be read; callers must separately require mutable destinations.
  bool containsNative(FlowValue address, NativeTypeRef storage) =>
      _containsNative(
        resolveValue(address),
        memoryLayout?.nativeLayout.of(storage).size,
      );

  /// References held anywhere in the addressed storage, excluding its owner.
  /// Unknown backing storage can contain any reference.
  FlowValue nativeReferences(FlowValue address) {
    address = resolveValue(address);
    final unknown = FlowValue.unknown(.object.nullable);
    var value =
        address.addresses.isEmpty ||
            address.objects.isNotEmpty ||
            address.constants.isNotEmpty ||
            address.unknownTypes.isNotEmpty
        ? unknown
        : const FlowValue.bottom();
    for (final pointer in address.addresses) {
      value = value.join(_memoryOf(pointer.base)?.references ?? unknown);
    }
    return value;
  }

  bool isMappedAddress(FlowValue value) =>
      value.managedBackings.isEmpty &&
      !value.hasUnknownBacking &&
      value.addresses.every(
        (address) =>
            address.base is FlowRegion &&
            address.type == ValueType.integer &&
            !address.retainedBase,
      ) &&
      _containsNative(value, 1);

  bool _containsNative(FlowValue address, int? size) =>
      size != null &&
      address.addresses.isNotEmpty &&
      address.objects.isEmpty &&
      address.constants.isEmpty &&
      address.unknownTypes.isEmpty &&
      address.addresses.every(
        (pointer) =>
            pointer.offsets != null &&
            (_memoryOf(pointer.base)?.containsRange(pointer.offsets!, size) ??
                false),
      );

  ({FlowValue address, int? size}) _nativeWriteRange(
    Instruction operation,
    List<FlowValue> operands,
  ) => switch (operation) {
    StoreNative(:final nativeType) || CopyNative(:final nativeType) => (
      address: operands.first,
      size: memoryLayout?.nativeLayout.of(nativeType).size,
    ),
    StoreObjectData(:final nativeType) => (
      address: _objectAddress(operands.first, operands[1]),
      size: memoryLayout?.nativeLayout.of(nativeType).size,
    ),
    StoreObjectReference() => (
      address: _objectAddress(operands.first, operands[1]),
      size: _referenceSlot(operands.first, operands[1])
          ? ObjectHeader.alignment
          : null,
    ),
    _ => throw ArgumentError('Expected a native storage write.'),
  };

  /// Whether every possible write stays within an existing mutable allocation.
  /// Uses the same address, representation and extent checks as the transfer.
  bool boundsNativeWrite(Instruction operation, List<FlowValue> operands) {
    if (operands.length != operation.inputs.length) {
      throw ArgumentError('Native write proof requires every operand.');
    }
    final range = _nativeWriteRange(
      operation,
      operands.map(resolveValue).toList(),
    );
    return operation is CopyNative && range.size == 0 ||
        _boundedMutableNative(range.address, range.size);
  }

  /// Proves a native leaf's complete written interval from its actual arguments.
  bool boundsNativeRange(FlowValue address, FlowValue length) {
    final count = length.integers;
    if (count?.constant == 0) return true;
    return _boundedMutableNative(
      resolveValue(address),
      count != null && count.lower >= 0 ? count.upper : null,
    );
  }

  bool _boundedMutableNative(FlowValue address, int? size) =>
      _containsNative(address, size) &&
      address.addresses.every((pointer) {
        final object = switch (pointer.base) {
          final FlowObject object => object,
          FlowRegion(:final allocation) => allocation,
          _ => null,
        };
        return object != null &&
            switch (object.site) {
              NativeDataAddress(declaration: NativeData(writable: false)) =>
                false,
              _ => true,
            };
      });

  /// Invalidates only a native call's written range, without following its contents.
  FlowState overwriteNative(
    FlowValue address,
    FlowValue length, {
    bool release = false,
  }) {
    final count = length.integers;
    if (count?.constant == 0) return copy();
    final size = count != null && count.lower >= 0 ? count.upper : null;
    return _writeNative(
      resolveValue(address),
      size,
      const .bottom(),
      (memory, offset) => release
          ? FlowMemory(memory.start, null)
          // WrittenMemory bounds possible writes; it does not promise that
          // every byte in the interval is overwritten, even for an exact size.
          : memory.join(memory.forget(offset, size!)),
    );
  }

  FlowState _writeNative(
    FlowValue address,
    int? size,
    FlowValue stored,
    FlowMemory Function(FlowMemory, int) write, {
    int? writeWidth,
  }) {
    if (address.addresses.any((pointer) => pointer.base is FlowMetadata)) {
      throw StateError('Cannot write immutable module metadata.');
    }
    final next = copy();
    next._recordRawSlotWrites(address, writeWidth ?? size);
    if (!_containsNative(address, size) ||
        address.addresses.any(
          (pointer) =>
              pointer.base is! FlowObject && pointer.base is! FlowRegion,
        )) {
      // An unbounded offset can reach other allocations, not just its base.
      next._invalidateRaw();
      next.escape([stored]);
      return next;
    }
    final strong = address.addresses.length == 1;
    for (final pointer in address.addresses) {
      final native = pointer.base is FlowRegion;
      final object = native
          ? (pointer.base as FlowRegion).allocation
          : pointer.base as FlowObject;
      if (object.site case NativeDataAddress(
        declaration: NativeData(writable: false),
      )) {
        throw StateError('Cannot write immutable native module storage.');
      }
      final state = (native ? _regions : _objects)[object]!;
      final offsets = pointer.offsets!;
      final memory = offsets.constant != null
          ? write(state.memory!, offsets.constant!)
          : state.memory!.join(
              state.memory!.forget(
                offsets.lower,
                offsets.upper - offsets.lower + size!,
                retained: stored,
              ),
            );
      var updated = (native ? next._regions : next._objects)[object]!
          .withMemory(
            strong && !state.summary
                ? memory
                : (native ? next._regions : next._objects)[object]!.memory!
                      .join(memory),
          );
      if (native) {
        next._recordWrite(object, _regionWrites);
        next._regions = next._regions.withEntry(object, updated);
        continue;
      }
      next._recordWrite(object, _objectMemoryWrites);
      if (offsets.upper + size! > ObjectHeader.fieldsOffset &&
          offsets.lower <
              (memoryLayout?.objectLayout(object.storageType!).size ??
                  ObjectHeader.fieldsOffset)) {
        for (final entry in updated.slots.entries) {
          if (entry.key case final InstanceField field) {
            next._recordWrite(object, field);
            updated = updated.withSlot(
              field,
              entry.value.invalidateRaw(
                field.typeFor(object.storageType!),
                isLate: field.isLate,
              ),
            );
          }
        }
      }
      next._objects = next._objects.withEntry(object, updated);
    }
    next.escape(const []);
    return next;
  }

  // A native write is legal in its own right. Its address capability determines
  // which later unchecked reads can no longer rely on the allocation contract.
  void _recordRawSlotWrites(FlowValue address, int? size) {
    if (size == 0) return;
    final layout = memoryLayout;
    void record(FlowObject object, FlowIntegerRange? offsets) {
      final view = object.storageView;
      var state = _objects[object];
      if (view == null || state == null) return;
      for (final field in view.fields.keys) {
        final slot = state!.slots[field];
        if (slot == null || slot.rawOverwrite) continue;
        final offset = layout is FlowFieldLayout
            ? (layout as FlowFieldLayout).fieldOffset(field)
            : null;
        final start = offset ?? ObjectHeader.fieldsOffset;
        final end = offset == null
            ? layout?.objectLayout(view.storageType).size
            : offset + ObjectHeader.alignment;
        if (offsets != null &&
            (size != null && offsets.upper <= start - size ||
                end != null && offsets.lower >= end)) {
          continue;
        }
        _recordWrite(object, field);
        state = state.withSlot(field, slot.withRawOverwrite());
      }
      _objects = _objects.withEntry(object, state!);
    }
    for (final pointer in address.addresses) {
      if (pointer.base case final FlowObject object) record(object, pointer.offsets);
    }
    if (address.unknownTypes.isNotEmpty) {
      for (final object in address.references.objects) {
        record(object, null);
      }
    }
  }

  /// Whether the declared logical field can still be read without a check.
  bool hasIntactSlot(FlowObject object, InstanceField field) =>
      _objects[object]?.slots[field]?.rawOverwrite == false;

  void _invalidateRaw() {
    for (final region in _regions.keys) {
      _recordWrite(region, _regionWrites);
    }
    _regions = _regions.mapValues(
      (_, region) => region.withMemory(region.memory!.invalidate()),
    );
    for (final global in _declaredGlobals) {
      _recordWrite(null, global);
      _setGlobal(
        global,
        (_globals[global] ?? _initial(global)).invalidate(
          global.type,
          isFinal: false,
        ),
      );
    }
    _objects = _objects.mapValues((object, state) {
      for (final key in state.slots.keys) {
        _recordWrite(object, key);
      }
      if (state.memory != null) _recordWrite(object, _objectMemoryWrites);
      if (state.captures != null) _recordWrite(object, _captureWrites);
      final slots = state.slots.mapValues((key, slot) {
        final type = key is InstanceField
            ? key.typeFor(object.storageType!)
            : (object.type as CellType).content;
        return slot.invalidateRaw(
          type,
          isLate: key is InstanceField
              ? key.isLate
              : (object.type as CellType).isLate,
        );
      });
      return _ObjectState._(
        slots,
        state.captures
            ?.map(
              (v) => v.join(
                v.types.fold<FlowValue>(
                  const .bottom(),
                  (value, type) => value.join(FlowValue.unknown(type)),
                ),
              ),
            )
            .toList(growable: false),
        state.summary,
        state.memory?.invalidate(),
      );
    });
  }

  FlowValue? _constantField(Constant constant, InstanceField field) {
    final layout = memoryLayout;
    if (constant is FunctionConstant && layout is FlowCallableLayout) {
      return switch ((layout as FlowCallableLayout).callableConstantField(
        constant,
        field,
      )) {
        final Constant value => FlowValue.constant(value),
        FunctionEntryTableAddress(:final target) => FlowValue.address(
          FlowAddress(target, 0),
        ),
        null => null,
        _ => throw StateError('Callable constant fields cannot execute code.'),
      };
    }
    final view = switch (constant) {
      TypeConstant() when layout is FlowTypeLayout =>
        (layout as FlowTypeLayout).typeConstant(constant),
      TypeConstant() => throw StateError(
        'Reading built-in type metadata requires a shared type layout.',
      ),
      ObjectConstant() => constant,
      _ => null,
    };
    final value = view?.fields[field];
    if (constant is TypeConstant && value == null) {
      throw StateError('The built-in type representation has no field $field.');
    }
    final result = value is ObjectConstant && layout is FlowTypeLayout
        ? (layout as FlowTypeLayout).canonicalTypeConstant(value) ?? value
        : value;
    return result == null ? null : FlowValue.constant(result);
  }

  FlowResult _readObjects(
    FlowValue receiver,
    Object key,
    ValueType resultType, {
    required FlowInvoke invoke,
    required FlowCall call,
  }) {
    var result = _unreachable;
    for (final object in receiver.objects) {
      final field = key is InstanceField ? key : null;
      final cell = field == null ? object.type as CellType : null;
      final type = field?.typeFor(object.storageType!) ?? cell!.content;
      final slot = _objects[object]?.slots[key];
      if (slot == null) {
        result = _merge(
          result,
          _unknownRead(.object(object), key, type, invoke: invoke, call: call),
        );
        continue;
      }
      var read = _read(
        (object, key),
        type,
        isFinal: field?.isFinal ?? cell!.isFinal,
        initialize: field != null
            ? field.initializer == null
                  ? null
                  : (input) =>
                        invoke(field.initializer!, [.object(object)], input)
            : slot.initializer.isBottom
            ? null
            : (input) => call(slot.initializer, [], input),
      );
      if (field != null && _weak(field) && read.normal != null) {
        read = FlowResult(
          value: read.value.join(_null),
          normal: read.normal,
          exceptional: read.exceptional,
          allocationFailureOnly: read.allocationFailureOnly,
          exception: read.exception,
          stackTrace: read.stackTrace,
          effects: read.effects,
        );
      }
      if (field?.requiresReadCheck ?? false) {
        read = _checkedRead(read, resultType);
      }
      result = _merge(result, read);
    }
    for (final constant in receiver.constants) {
      if (key is InstanceField) {
        final value = _constantField(constant, key);
        if (value != null) {
          var read = _normal(value, copy());
          if (_weak(key)) read = _normal(read.value.join(_null), read.normal!);
          if (key.requiresReadCheck) read = _checkedRead(read, resultType);
          result = _merge(result, read);
          continue;
        }
      }
      result = _merge(
        result,
        _unknownRead(
          .constant(constant),
          key,
          resultType,
          invoke: invoke,
          call: call,
        ),
      );
    }
    for (final bound in receiver.unknownTypes) {
      result = _merge(
        result,
        _unknownRead(
          .unknown(
            bound,
            external: receiver.externalUnknownTypes.contains(bound),
          ),
          key,
          resultType,
          invoke: invoke,
          call: call,
        ),
      );
    }
    return _withEffects(result, const {Effect.readsStorage});
  }

  FlowResult _unknownRead(
    FlowValue receiver,
    Object key,
    ValueType type, {
    required FlowInvoke invoke,
    required FlowCall call,
  }) {
    final field = key is InstanceField ? key : null;
    final cell = field == null ? receiver.types.single as CellType : null;
    final external =
        receiver.unknownTypes.isNotEmpty &&
        receiver.externalUnknownTypes.containsAll(receiver.unknownTypes);
    var result = _normal(FlowValue.unknown(type, external: external), copy());
    if (field?.isLate ?? cell!.isLate) {
      final initialized = field == null
          ? call(.unknown(FunctionType(type, [])), [], copy())
          : field.initializer == null
          ? _unreachable
          : invoke(field.initializer!, [receiver], copy());
      if (initialized.normal case final normal?) {
        final committed = normal._writeObjects(
          receiver,
          key,
          initialized.value,
        );
        result = _merge(
          result,
          FlowResult(
            value: committed.normal == null
                ? const .bottom()
                : .unknown(type, external: external),
            normal: committed.normal,
            exceptional: committed.exceptional,
            allocationFailureOnly: committed.allocationFailureOnly,
            exception: committed.exception,
            stackTrace: committed.stackTrace,
            effects: committed.effects,
          ),
        );
      }
      result = _merge(
        result,
        FlowResult(
          value: const .bottom(),
          normal: null,
          exceptional: initialized.exceptional,
          allocationFailureOnly: initialized.allocationFailureOnly,
          exception: initialized.exception,
          stackTrace: initialized.stackTrace,
        ),
      );
      result = _merge(
        result,
        FlowResult(
          value: const .bottom(),
          normal: null,
          exceptional: _joinStates(this, initialized.normal),
          exception: _bindingError,
        ),
      );
    } else if (field?.requiresReadCheck ?? false) {
      result = FlowResult(
        value: result.value,
        normal: result.normal,
        exceptional: copy(),
        exception: _typeError,
      );
    }
    return _withEffects(result, const {Effect.readsStorage});
  }

  FlowResult _copyFieldSlot(InstanceField field, FlowValue destination,
      FlowValue source) {
    if (source.isBottom || destination.isBottom) return _unreachable;
    _Slot? copied;
    void add(_Slot slot) => copied = copied == null ? slot : copied!.join(slot);
    _Slot unknownSlot(ValueType type, {bool external = false}) => _Slot._(
        FlowValue.unknown(type, external: external), true, const FlowValue.bottom());
    for (final object in source.objects) {
      add(_objects[object]?.slots[field] ?? unknownSlot(field.typeFor(object.storageType!)));
    }
    for (final constant in source.constants) {
      final value = _constantField(constant, field);
      add(value == null ? unknownSlot(field.type) : _Slot.bound(value));
    }
    for (final type in source.unknownTypes) {
      add(unknownSlot(type is ClassType ? field.typeFor(type) : field.type,
          external: source.externalUnknownTypes.contains(type)));
    }
    if (copied == null) return _unreachable;
    final next = copy();
    final unknown = FlowValue.joined([
      for (final type in destination.unknownTypes)
        FlowValue.unknown(type, external: destination.externalUnknownTypes.contains(type)),
      for (final value in destination.constants) FlowValue.unknown(value.type),
    ]);
    final aliases = _unknownAliases(unknown);
    final targets = {...destination.objects, ...aliases};
    for (final object in targets) {
      final old = next._objects[object]?.slots[field];
      if (old == null) continue;
      final weak = destination.objects.length != 1 || aliases.contains(object);
      next._recordWrite(object, field);
      next._set((object, field), weak ? old.join(copied!) : copied!);
      next._forgetFieldBytes(object);
    }
    if (unknown.unknownTypes.isNotEmpty) next.escape([copied!.value]);
    return _withEffects(_normal(_null, next), const {
      Effect.readsStorage, Effect.writesStorage,
    });
  }

  FlowResult _writeObjects(FlowValue receiver, Object key, FlowValue value) {
    if (value.isBottom) return _unreachable;
    var result = _unreachable;
    var unknown = FlowValue.joined([
      for (final type in receiver.unknownTypes)
        FlowValue.unknown(
          type,
          external: receiver.externalUnknownTypes.contains(type),
        ),
      for (final value in receiver.constants) FlowValue.unknown(value.type),
    ]);
    for (final object in receiver.objects) {
      final field = key is InstanceField ? key : null;
      final cell = field == null ? object.type as CellType : null;
      if (_objects[object]?.slots[key] == null) {
        unknown = unknown.join(FlowValue.unknown(object.type));
        continue;
      }
      result = _merge(
        result,
        _write(
          (object, key),
          value,
          field?.typeFor(object.storageType!) ?? cell!.content,
          isFinal: field == null
              ? cell!.isFinal
              : field.isLate && field.isFinal,
        ),
      );
    }
    if (unknown.unknownTypes.isNotEmpty) {
      // Capture the receiver's aliases before exposing the stored value.
      final aliases = _unknownAliases(unknown);
      final next = copy()..escape([value]);
      for (final object in next._objects.keys) {
        final state = next._objects[object]!;
        if (!aliases.contains(object)) {
          continue;
        }
        final slot = state.slots[key];
        if (slot == null) {
          if (key is InstanceField) next._forgetFieldBytes(object);
          continue;
        }
        final type = key is InstanceField
            ? key.typeFor(object.storageType!)
            : (object.type as CellType).content;
        final isFinal = key is InstanceField
            ? key.isLate && key.isFinal
            : (object.type as CellType).isFinal;
        if (isFinal && !slot.unbound) continue;
        final checked = value.check(type);
        if (!checked.value.isBottom) {
          next._recordWrite(object, key);
          next._objects = next._objects.withEntry(
            object,
            state.withSlot(key, slot.join(_Slot.bound(checked.value))),
          );
          if (key is InstanceField) next._forgetFieldBytes(object);
        }
      }
      result = _merge(
        result,
        FlowResult(
          value: _null,
          normal: next,
          exceptional: copy(),
          exception: _bindingError,
          effects: {
            Effect.writesStorage,
            if (key is InstanceField
                ? key.isLate && key.isFinal
                : receiver.types.any((t) => t is CellType && t.isFinal))
              Effect.readsStorage,
          },
        ),
      );
    }
    return result;
  }

  FlowResult _read(
    (FlowObject?, Object) location,
    ValueType type, {
    required bool isFinal,
    required FlowResult Function(FlowState)? initialize,
  }) {
    final slot = _slot(location);
    var result = _unreachable;
    if (!slot.value.isBottom) {
      final value = resolveValue(slot.value);
      final bound = copy().._refine(location, _Slot.bound(value));
      result = _normal(value, bound);
    }
    if (slot.unbound) {
      final unbound = copy()
        .._refine(location, _Slot.unbound(initializer: slot.initializer));
      if (initialize == null) {
        result = _merge(
          result,
          FlowResult(
            value: const .bottom(),
            normal: null,
            exceptional: unbound,
            exception: _bindingError,
          ),
        );
      } else {
        final initialized = initialize(unbound);
        var bound = FlowResult(
          value: const FlowValue.bottom(),
          normal: null as FlowState?,
          exceptional: initialized.exceptional,
          allocationFailureOnly: initialized.allocationFailureOnly,
          exception: initialized.exception,
          stackTrace: initialized.stackTrace,
        );
        if (initialized.normal case final normal?) {
          bound = _merge(
            bound,
            normal._write(location, initialized.value, type, isFinal: isFinal),
          );
        }
        result = _merge(result, bound);
      }
    }
    return _withEffects(result, const {Effect.readsStorage});
  }

  FlowResult _write(
    (FlowObject?, Object) location,
    FlowValue value,
    ValueType type, {
    required bool isFinal,
  }) {
    final checked = value.check(type);
    FlowState? exceptional = checked.mayFail ? copy() : null;
    var exception = checked.mayFail ? _typeError : const FlowValue.bottom();
    if (checked.value.isBottom) {
      return FlowResult(
        value: const .bottom(),
        normal: null,
        exceptional: exceptional,
        exception: exception,
        effects: const {Effect.readsStorage},
      );
    }
    final slot = _slot(location);
    if (isFinal && !slot.value.isBottom) {
      final bound = copy().._refine(location, _Slot.bound(slot.value));
      exceptional = _joinStates(exceptional, bound);
      exception = exception.join(_bindingError);
    }
    if (isFinal && !slot.unbound) {
      return FlowResult(
        value: const .bottom(),
        normal: null,
        exceptional: exceptional,
        exception: exception,
        effects: const {Effect.readsStorage},
      );
    }
    final next = copy();
    next._recordWrite(location.$1, location.$2);
    next._set(location, _Slot.bound(checked.value));
    if (location case (final FlowObject object, InstanceField())) {
      next._forgetFieldBytes(object);
    }
    return FlowResult(
      value: checked.value,
      normal: next,
      exceptional: exceptional,
      exception: exception,
      effects: {Effect.writesStorage, if (isFinal) Effect.readsStorage},
    );
  }

  void _allocate(FlowObject object, _ObjectState state) {
    final prior = _objects[object];
    for (final key in state.slots.keys) {
      _recordWrite(object, key);
    }
    if (state.memory != null) _recordWrite(object, _objectMemoryWrites);
    if (state.captures != null) _recordWrite(object, _captureWrites);
    // Existing input storage denotes an earlier allocation, not a solver revisit.
    _objects = _objects.withEntry(
      object,
      prior == null ? state : prior.join(state).withFlags(summary: true),
    );
  }

  void _forgetFieldBytes(FlowObject object) {
    final state = _objects[object]!;
    final memory = state.memory;
    if (memory == null || memoryLayout == null) return;
    _recordWrite(object, _objectMemoryWrites);
    _objects = _objects.withEntry(
      object,
      state.withMemory(
        memory.forget(
          ObjectHeader.fieldsOffset,
          memoryLayout!.objectLayout(object.storageType!).size -
              ObjectHeader.fieldsOffset,
        ),
      ),
    );
  }

  _Slot _slot((FlowObject?, Object) location) => location.$1 == null
      ? _globals[location.$2 as GlobalVariable] ??
            _initial(location.$2 as GlobalVariable)
      : _objects[location.$1!]!.slots[location.$2]!;

  void _set((FlowObject?, Object) location, _Slot slot) {
    if (_slot(location) == slot) return;
    final object = location.$1;
    if (object == null) {
      _setGlobal(location.$2 as GlobalVariable, slot);
    } else {
      final state = _objects[object]!;
      _objects = _objects.withEntry(
        object,
        state.withSlot(
          location.$2,
          state.summary ? state.slots[location.$2]!.join(slot) : slot,
        ),
      );
    }
  }

  void _refine((FlowObject?, Object) location, _Slot slot) {
    final object = location.$1;
    if (object == null || !_objects[object]!.summary) {
      _set(location, slot);
    }
  }

  void _requireGlobal(GlobalVariable global) {
    if (!_declaredGlobals.contains(global)) {
      throw ArgumentError('Global does not belong to this IR graph.');
    }
  }

  IrClass? _class(ClassType type) => _classes[type.declaration];

  bool _weak(InstanceField field) {
    final definition = _class(field.owner);
    return definition != null &&
        (definition.weakFields.contains(field) ||
            definition.ephemerons.containsKey(field) ||
            definition.ephemerons.containsValue(field));
  }

  /// Contents already bound on every path, without performing the read.
  ///
  /// Lazy, weak and unknown-receiver reads have no unconditional stored value.
  FlowValue? boundValueOf(Instruction read, List<FlowValue> operands) {
    if (operands.length != read.inputs.length) {
      throw ArgumentError('Storage operands must match the read instruction.');
    }
    if (read is LoadObjectReference) {
      return _readReference(operands.first, operands.last);
    }
    if (read case LoadGlobal(:final global)) {
      _requireGlobal(global);
      final slot = _globals[global] ?? _initial(global);
      return slot.unbound ? null : resolveValue(slot.value);
    }
    final Object key;
    switch (read) {
      case LoadField(:final field):
        if (_weak(field)) return null;
        key = field;
      case ReadCell():
        key = _cell;
      default:
        throw ArgumentError('Expected a field, cell, global or payload read.');
    }
    final receiver = operands.single;
    if (receiver.isBottom || receiver.unknownTypes.isNotEmpty) return null;
    var value = const FlowValue.bottom();
    for (final object in receiver.objects) {
      final slot = _objects[object]?.slots[key];
      if (slot == null || slot.unbound) return null;
      value = value.join(resolveValue(slot.value));
    }
    for (final constant in receiver.constants) {
      if (key is! InstanceField) return null;
      final field = _constantField(constant, key);
      if (field == null) return null;
      value = value.join(field);
    }
    return value;
  }

  /// Bound field contents, without running an unbound initializer.
  FlowValue storedValue(FlowObject object, InstanceField field) => resolveValue(
    _objects[object]?.slots[field]?.value ??
        FlowValue.unknown(field.typeFor(object.storageType!)),
  );

  /// Records a completed read of one definite, strong storage location.
  void rememberRead(
    Instruction read,
    List<FlowValue> operands,
    FlowSource source,
  ) {
    if (operands.length != read.inputs.length ||
        !identical(source.value, read)) {
      throw ArgumentError(
        'A stored read requires its operands and SSA source.',
      );
    }
    if (read case LoadNative(nativeType: final NativeTypeRef storage)) {
      final address = operands.single;
      final pointer = address.addresses.singleOrNull;
      if (address.constants.isEmpty &&
          address.unknownTypes.isEmpty &&
          address.objects.isEmpty &&
          !address.hasUnknownBacking &&
          address.managedBackings.isEmpty &&
          pointer != null &&
          !pointer.retainedBase &&
          pointer.offset != null &&
          pointer.base is FlowRegion) {
        final allocation = (pointer.base as FlowRegion).allocation;
        final prior = _regions[allocation];
        if (prior != null &&
            !prior.summary &&
            prior.memory != null &&
            memoryLayout != null &&
            storage
                    .resolveAbi(memoryLayout!.nativeLayout.target.abi)
                    .integerLayout
                    ?.bytes ==
                8) {
          _regions = _regions.withEntry(
            allocation,
            prior.withMemory(
              prior.memory!.rememberWord(pointer.offset!, source),
            ),
          );
        }
      }
      return;
    }
    if (read case LoadGlobal(:final global)) {
      _requireGlobal(global);
      final slot = _globals[global] ?? _initial(global);
      if (!slot.unbound) {
        _setGlobal(
          global,
          _Slot._(
            slot.value.withSource(read, source.activation),
            slot.unbound,
            slot.initializer,
            slot.rawOverwrite,
          ),
        );
      }
      return;
    }
    final key = switch (read) {
      LoadField(:final field) when !_weak(field) => field,
      ReadCell() => _cell,
      _ => null,
    };
    if (key == null) return;
    final receiver = operands.single;
    if (receiver.objects.length != 1 ||
        receiver.constants.isNotEmpty ||
        receiver.unknownTypes.isNotEmpty ||
        receiver.addresses.isNotEmpty) {
      return;
    }
    final object = receiver.objects.single;
    final state = _objects[object];
    final slot = state?.slots[key];
    if (state == null || state.summary || slot == null || slot.unbound) return;
    _objects = _objects.withEntry(
      object,
      state.withSlot(
        key,
        _Slot._(
          slot.value.withSource(read, source.activation),
          slot.unbound,
          slot.initializer,
          slot.rawOverwrite,
        ),
      ),
    );
  }

  /// Values accessible through current fields, cells and closure captures.
  FlowValue reachableValues(Iterable<FlowValue> roots) =>
      _reachable(roots, expose: false);

  /// External access follows ordinary slots; raw addresses also expose captures.
  FlowValue exposedFrom(Iterable<FlowValue> roots) =>
      _reachable(roots, expose: true);

  Set<FlowObject> _externalAliasObjects() => _reachable(
    [
      _externalAliases,
      _escaped,
      for (final object in _moduleObjects.values)
        if (_objects[object] != null) FlowValue.object(object),
      for (final slot in _globals.values) ...[slot.value, slot.initializer],
      for (final binding in [..._externalMemory.values, ..._nativeData.values])
        if (_regions[binding.allocation] != null)
          FlowValue.address(FlowAddress(FlowRegion(binding.allocation), 0)),
    ],
    expose: true,
    expandExternal: false,
  ).objects;

  Set<FlowObject> _unknownAliases(
    FlowValue value, {
    bool memory = false,
    bool includeRegions = false,
  }) {
    if (value.unknownTypes.isEmpty) return const {};
    final external = value.externalUnknownTypes.isEmpty
        ? const <FlowObject>{}
        : _externalAliasObjects();
    return {
      for (final object in [
        ..._objects.keys,
        if (includeRegions) ..._regions.keys,
      ])
        if (value.unknownTypes.any(
          (type) =>
              (memory || _mayAliasObject(type, object)) &&
              (!value.externalUnknownTypes.contains(type) ||
                  external.contains(object)),
        ))
          object,
    };
  }

  FlowValue _reachable(
    Iterable<FlowValue> roots, {
    required bool expose,
    FlowStorageAccess? access,
    bool constants = true,
    bool expandExternal = true,
  }) {
    final values = <FlowValue>[];
    final pending = [for (final value in roots) (value, !expose)];
    final directValues = Set<FlowValue>.identity();
    final rawValues = Set<FlowValue>.identity();
    final objects = <(FlowObject, bool)>{};
    final regions = <FlowObject>{};
    final visitedConstants = <(Object, bool)>{};
    // The object graph is fixed for this traversal. Expand each unknown bound
    // once per capability; raw access can additionally reveal closure captures.
    final unknowns = <(ValueType, bool, bool)>{};
    // Project unknown references by distinct runtime type and capability,
    // not by re-walking the inheritance graph for every heap identity.
    // This partition belongs to this fixed traversal; no result is reused
    // across states, escaped-object sets or changes in the program graph.
    late final families = _aliasFamilies(_objects.keys);
    final externalVisits = <bool>{};
    late final externalObjects = _externalAliasObjects();
    while (pending.isNotEmpty) {
      final (input, raw) = pending.removeLast();
      if (!(raw ? rawValues : directValues).add(input)) continue;
      final value = resolveValue(input);
      values.add(value);
      if (!value.references.isBottom) pending.add((value.references, true));
      // A physical scalar carrier is retained by GC and summaries. Passing the
      // scalar to unknown Dart code does not grant access to its private bytes.
      if (!expose) {
        pending.addAll([
          for (final backing in value.managedBackings)
            (FlowValue.object(backing), false),
          if (value.hasUnknownBacking)
            for (final backing in _objects.keys)
              if (ExecutionShapes.forType(backing.type).isScalar &&
                  value.types.any((bound) => bound.accepts(backing.type)))
                (FlowValue.object(backing), false),
        ]);
      }
      // Only an actual byte/address observation creates these capabilities.
      // Unlike an unknown Dart scalar, the observed reference can address a
      // matching carrier even when its concrete allocation was not known.
      for (final bound in value.rawBackingTypes) {
        for (final backing in _objects.keys) {
          if (ExecutionShapes.forType(backing.type).isScalar &&
              bound.accepts(backing.type) && !objects.contains((backing, true))) {
            pending.add((FlowValue.object(backing), true));
          }
        }
      }
      // A runtime-unknown reference may alias an already modeled object. Keep
      // that possibility when following capabilities, including raw snapshots;
      // retaining only concrete identities would lose an overwritten pointee.
      for (final type in value.unknownTypes) {
        final external = value.externalUnknownTypes.contains(type);
        if (!unknowns.add((type, raw, external)) ||
            external && !expandExternal) {
          continue;
        }
        // A field of an external unknown owner may lead to any already exposed
        // object. No type-only edge may introduce a later private allocation.
        void follow(Iterable<FlowObject> members) {
          for (final object in members) {
            if (!value.objects.contains(object) && !objects.contains((object, raw))) {
              pending.add((FlowValue.object(object), raw));
            }
          }
        }

        if (external) {
          if (externalVisits.add(raw)) {
            follow(externalObjects.where((object) => !_isScalarValue(object.type)));
          }
        } else {
          for (final members in families.values) {
            if (_mayAliasObject(type, members.first)) follow(members);
          }
        }
      }
      for (final address in value.addresses) {
        if (address.base case FlowRegion(:final allocation)
            when regions.add(allocation)) {
          if (_regions[allocation]?.memory case final memory?) {
            pending.add((memory.references, true));
          }
        }
      }
      for (final object in value.objects) {
        if (!objects.add((object, raw))) continue;
        final state = _objects[object];
        if (state == null) continue;
        if (state.memory case final memory?
            when access == null || access.memory) {
          pending.add((memory.references, true));
        }
        if (raw && (access == null || access.memory)) {
          pending.addAll([
            for (final capture in state.captures ?? const <FlowValue>[])
              (capture, raw),
          ]);
        }
        for (final entry in _readSlots(object, state, access)) {
          final slot = entry.value;
          pending.add((slot.value, raw));
          if (raw && slot.unbound) pending.add((slot.initializer, raw));
        }
      }
      // Immutable constants cannot lead to mutable object identities.
      if (!constants) continue;
      for (final constant in value.constants) {
        if (!visitedConstants.add((constant.structuralKey, raw))) continue;
        final nested = switch (constant) {
          ObjectConstant(:final fields, :final payload) =>
            fields.values.followedBy(payload),
          RecordConstant(:final fields) => fields,
          SequenceConstant(:final elements) => elements,
          MapConstant(:final entries) => entries.expand((e) => [e.$1, e.$2]),
          _ => const <Constant>[],
        };
        pending.addAll([
          for (final child in nested) (FlowValue.constant(child), raw),
        ]);
      }
    }
    return FlowValue.joined(values);
  }
}

Map<(ValueType, CellType?), List<FlowObject>> _aliasFamilies(Iterable<FlowObject> objects) {
  final families = <(ValueType, CellType?), List<FlowObject>>{};
  for (final object in objects) {
    final cell = object.storageView?.capability;
    final key = (object.type, cell is CellType && object.hasCellType(cell) ? cell : null);
    (families[key] ??= []).add(object);
  }
  return families;
}

// Projection and writes must agree on possible aliases, including unresolved
// generic bounds. Assignability alone is too strict for a runtime instance.
bool _mayAliasObject(ValueType bound, FlowObject object) =>
    bound is CellType && object.hasCellType(bound) ||
    _mayAliasType(bound, object.type);

bool _mayAliasType(ValueType bound, ValueType actual) =>
    !_isScalarValue(actual) &&
    (actual is ClassType
        ? bound.mayHaveInstance(actual)
        : bound.accepts(actual));

bool _isScalarValue(ValueType type) =>
    ValueType.number.nullable.accepts(type) ||
    ValueType.boolean.nullable.accepts(type);

Iterable<MapEntry<Object, _Slot>> _readSlots(
  FlowObject object,
  _ObjectState state,
  FlowStorageAccess? access,
) => access == null || access.memory
    ? state.slots.entries
    : state.slots.entries.where(
        (entry) => entry.key == _cell
            ? access.cells
            : access.fields.contains(entry.key) || access.cells &&
                (object.cellStorage?.fields.contains(entry.key) ?? false),
      );

final _cell = Object();
final _globalWrites = Object();
final _objectMemoryWrites = Object();
final _regionWrites = Object();
final _mappedRegions = Object();
final _captureWrites = Object();
final _null = FlowValue.constant(const Constant.nullValue());
final _typeError = FlowValue.unknown(ValueType.typeError);
final _bindingError = FlowValue.unknown(ValueType.error);
const FlowResult _unreachable = FlowResult(
  value: FlowValue.bottom(),
  normal: null,
  exceptional: null,
);

FlowResult _normal(FlowValue value, FlowState state) =>
    FlowResult(value: value, normal: state, exceptional: null);

FlowState? _joinStates(FlowState? left, FlowState? right) {
  if (left == null) return right?.copy();
  if (right == null) return left.copy();
  return left.copy()..join(right);
}

FlowResult _merge(FlowResult left, FlowResult right) => FlowResult(
  value: left.value.join(right.value),
  normal: _joinStates(left.normal, right.normal),
  exceptional: _joinStates(left.exceptional, right.exceptional),
  allocationFailureOnly: !left.hasSemanticFailure && !right.hasSemanticFailure,
  exception: left.exception.join(right.exception),
  stackTrace: left.stackTrace.join(right.stackTrace),
  effects: Set.unmodifiable({...left.effects, ...right.effects}),
);

FlowResult _withEffects(FlowResult result, Set<Effect> effects) => FlowResult(
  value: result.value,
  normal: result.normal,
  exceptional: result.exceptional,
  allocationFailureOnly: result.allocationFailureOnly,
  exception: result.exception,
  stackTrace: result.stackTrace,
  effects: Set.unmodifiable({...result.effects, ...effects}),
);

FlowResult _checkedRead(FlowResult result, ValueType type) {
  if (result.normal == null) return result;
  final checked = result.value.check(type, runtimeTypes: true);
  return _merge(
    FlowResult(
      value: checked.value,
      normal: checked.value.isBottom ? null : result.normal,
      exceptional: result.exceptional,
      allocationFailureOnly: result.allocationFailureOnly,
      exception: result.exception,
      stackTrace: result.stackTrace,
      effects: result.effects,
    ),
    checked.mayFail
        ? FlowResult(exceptional: result.normal, exception: _typeError)
        : _unreachable,
  );
}

final class _Slot {
  final FlowValue value;
  final bool unbound;
  final FlowValue initializer;
  final bool rawOverwrite;

  const new unbound({this.initializer = const .bottom()})
    : rawOverwrite = false,
      value = const .bottom(),
      unbound = true;
  const new bound(this.value)
    : rawOverwrite = false, unbound = false, initializer = const .bottom();
  new unknown(ValueType type)
    : rawOverwrite = false,
      value = .unknown(type),
      unbound = true,
      initializer = .unknown(FunctionType(type, []));
  const new _(this.value, this.unbound, this.initializer, [this.rawOverwrite = false]);

  _Slot join(_Slot other, {bool widen = false}) => _Slot._(
    value.join(other.value, widen: widen),
    unbound || other.unbound,
    initializer.join(other.initializer, widen: widen),
    rawOverwrite || other.rawOverwrite,
  );

  _Slot map(FlowValue Function(FlowValue) transform) {
    final mapped = _Slot._(transform(value), unbound, transform(initializer), rawOverwrite);
    return mapped == this ? this : mapped;
  }

  bool permitsWrite(bool isFinal) => !isFinal || unbound;

  _Slot withRawOverwrite() =>
      rawOverwrite ? this : _Slot._(value, unbound, initializer, true);

  _Slot invalidate(ValueType type, {required bool isFinal}) =>
      permitsWrite(isFinal)
      ? _Slot._(value.join(.unknown(type)), unbound, initializer, rawOverwrite)
      : this;

  _Slot invalidateRaw(ValueType type, {required bool isLate}) =>
      isLate ? join(_Slot.unknown(type)) : invalidate(type, isFinal: false);

  @override
  bool operator ==(Object other) =>
      other is _Slot &&
      other.value == value &&
      other.rawOverwrite == rawOverwrite &&
      other.unbound == unbound &&
      other.initializer == initializer;
  @override
  int get hashCode => Object.hash(value, unbound, initializer, rawOverwrite);
}

final class _ObjectState {
  final StateMap<Object, _Slot> slots;
  final List<FlowValue>? captures;
  final bool summary;
  final FlowMemory? memory;

  new(
    Map<Object, _Slot> slots, {
    List<FlowValue>? captures,
    this.summary = false,
    this.memory,
  }) : slots = StateMap.fromEntries(slots.entries),
       captures = captures == null ? null : List.unmodifiable(captures);

  new _(this.slots, this.captures, this.summary, this.memory);

  _ObjectState withSlot(Object key, _Slot value) {
    final next = slots.withEntry(key, value);
    return identical(next, slots)
        ? this
        : _ObjectState._(next, captures, summary, memory);
  }

  _ObjectState withFlags({bool summary = false}) => !summary || this.summary
      ? this
      : _ObjectState._(slots, captures, true, memory);

  _ObjectState withMemory(FlowMemory? value) =>
      value == memory ? this : _ObjectState._(slots, captures, summary, value);

  _ObjectState map(FlowValue Function(FlowValue) transform) {
    final mappedSlots = slots.mapValues((_, value) => value.map(transform));
    final mappedCaptures = captures == null
        ? null
        : List<FlowValue>.unmodifiable(captures!.map(transform));
    final mappedMemory = memory?.map(transform);
    return mappedMemory == memory &&
            identical(mappedSlots, slots) &&
            _sameCaptures(mappedCaptures, captures)
        ? this
        : _ObjectState._(mappedSlots, mappedCaptures, summary, mappedMemory);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _ObjectState &&
          slots == other.slots &&
          summary == other.summary &&
          memory == other.memory &&
          _sameCaptures(captures, other.captures);

  @override
  late final int hashCode = Object.hash(
    slots,
    captures != null,
    Object.hashAll(captures ?? const <FlowValue>[]),
    summary,
    memory,
  );

  _ObjectState join(
    _ObjectState incoming, {
    bool widen = false,
    NativeWordProofs? nativeWords,
  }) {
    if (identical(this, incoming)) return this;
    final joinedSlots = slots.merge(
      incoming.slots,
      (_, left, right) => left == null
          ? right!
          : right == null
          ? left
          : left.join(right, widen: widen),
    );
    final joinedMemory = memory == null
        ? incoming.memory?.invalidate()
        : incoming.memory == null
        ? memory!.invalidate()
        : memory!.join(
            incoming.memory!,
            widen: widen,
            nativeWords: nativeWords,
          );
    var changed =
        joinedMemory != memory ||
        !identical(joinedSlots, slots) ||
        incoming.summary && !summary;
    var joinedCaptures = captures;
    if (incoming.captures case final other?) {
      if (captures == null) {
        joinedCaptures = other;
        changed = true;
      } else if (!identical(captures, other)) {
        if (captures!.length != other.length) {
          throw StateError('One closure allocation has incompatible captures.');
        }
        final joined = <FlowValue>[];
        var capturesChanged = false;
        for (var i = 0; i < other.length; i++) {
          final value = captures![i].join(other[i], widen: widen);
          capturesChanged |= value != captures![i];
          joined.add(value);
        }
        if (capturesChanged) joinedCaptures = List.unmodifiable(joined);
        changed |= capturesChanged;
      }
    }
    return changed
        ? _ObjectState._(
            joinedSlots,
            joinedCaptures,
            summary || incoming.summary,
            joinedMemory,
          )
        : this;
  }
}

bool _sameCaptures(List<FlowValue>? a, List<FlowValue>? b) =>
    identical(a, b) ||
    a != null &&
        b != null &&
        a.length == b.length &&
        a.indexed.every((entry) => entry.$2 == b[entry.$1]);
