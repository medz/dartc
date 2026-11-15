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

  /// Effects performed by this transfer itself, excluding source callees.
  final Set<Effect> effects = const {},
  FlowValue? exception,
  FlowValue? stackTrace,
}) {
  final FlowValue? _exception = exception;
  final FlowValue? _stackTrace = stackTrace;

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

/// Storage facts at one executable program point.
///
/// Transfers return independent exit snapshots. Allocation identities and call
/// scheduling belong to the program solver, including repetition in its CFG.
final class FlowState {
  /// The immutable semantic graph whose declarations identify slots.
  final IrProgram program;

  /// Explicit output storage; absent layouts never imply host memory facts.
  final FlowMemoryLayout? memoryLayout;
  final Set<GlobalVariable> _declaredGlobals;
  final Map<ClassType, IrClass> _classes;
  final Map<Object, FlowMemory> _constantMemory;
  StateMap<GlobalVariable, _Slot> _globals;
  StateMap<FlowObject, _ObjectState> _objects;
  FlowValue _escaped;

  new(this.program, {this.memoryLayout})
    : _declaredGlobals = Set.unmodifiable(program.globals),
      _classes = Map.unmodifiable({for (final c in program.classes) c.type: c}),
      _constantMemory = {},
      _globals = const .empty(),
      _objects = const .empty(),
      _escaped = const .bottom();

  new _(
    this.program,
    this.memoryLayout,
    this._declaredGlobals,
    this._classes,
    this._constantMemory,
    this._globals,
    this._objects,
    this._escaped,
  );

  /// Shares immutable storage versions; taking a point snapshot is O(1).
  FlowState copy() => FlowState._(
    program,
    memoryLayout,
    _declaredGlobals,
    _classes,
    _constantMemory,
    _globals,
    _objects,
    _escaped,
  );

  /// Keeps valid SSA equalities without changing stored values or prior snapshots.
  void retainSources(bool Function(FlowSource) retain) {
    _mapValues((value) => value.withSources(value.sources.where(retain)));
  }

  /// Applies path bounds to storage still equal to the checked SSA definitions.
  void refineIntegers(Map<FlowSource, FlowIntegerRange> ranges) {
    if (ranges.isEmpty) return;
    _mapValues((value) {
      for (final source in value.sources) {
        if (ranges[source] case final range?) {
          value = value.restrictIntegers(range);
        }
      }
      return value;
    });
  }

  void _mapValues(FlowValue Function(FlowValue) transform) {
    _globals = _globals.mapValues((_, slot) => slot.map(transform));
    _objects = _objects.mapValues((_, object) => object.map(transform));
    _escaped = transform(_escaped);
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
    final objects = _objects.isEmpty
        ? incoming._objects
        : incoming._objects.isEmpty
        ? _objects
        : _objects.merge(
            incoming._objects,
            (_, left, right) => left == null
                ? right!
                : right == null
                ? left
                : left.join(right, widen: widen),
          );
    final escaped = _escaped.join(incoming._escaped, widen: widen);
    final changed =
        !identical(globals, _globals) ||
        !identical(objects, _objects) ||
        escaped != _escaped;
    _globals = globals;
    _objects = objects;
    _escaped = escaped;
    return changed;
  }

  _Slot _initial(GlobalVariable global) =>
      !global.isLate && global.initializer == null
      ? _Slot.bound(_null)
      : const _Slot.unbound();

  /// An immutable key for the current version, safe after this wrapper changes.
  Object get structuralKey =>
      (program, memoryLayout, _globals, _objects, _escaped);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FlowState && structuralKey == other.structuralKey;

  @override
  int get hashCode => structuralKey.hashCode;

  /// Projects a call input while preserving globals and external reachability.
  FlowState project(Iterable<FlowValue> roots) {
    final reachable = reachableValues([
      ...roots,
      _escaped,
      for (final slot in _globals.values) ...[slot.value, slot.initializer],
    ]);
    var objects = const StateMap<FlowObject, _ObjectState>.empty();
    for (final object in reachable.objects) {
      if (_objects[object] case final state?) {
        objects = objects.withEntry(object, state);
      }
    }
    return FlowState._(
      program,
      memoryLayout,
      _declaredGlobals,
      _classes,
      _constantMemory,
      _globals,
      objects,
      _escaped,
    );
  }

  /// Applies a callee's changes after mapping its allocation and value identities.
  ///
  /// Unrelated caller storage is preserved. The returned wrapper is independent.
  /// [preservesInputSources] requires a callee proven not to mutate storage or
  /// trigger collection; its reads add aliases while preserving caller values.
  FlowState applySummary(
    FlowState before,
    FlowState after, {
    required FlowObject Function(FlowObject) mapObject,
    required FlowValue Function(FlowValue) mapValue,
    bool preservesInputSources = false,
  }) {
    if (!identical(program, before.program) ||
        !identical(program, after.program) ||
        !identical(memoryLayout, before.memoryLayout) ||
        !identical(memoryLayout, after.memoryLayout)) {
      throw ArgumentError(
        'A call summary belongs to one graph and target layout.',
      );
    }
    final result = copy();
    _Slot preserve(_Slot next, _Slot? previous) {
      if (!preservesInputSources || previous == null) return next;
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
      );
    }

    for (final change in after._globals.differences(before._globals)) {
      result._setGlobal(
        change.key,
        preserve(
          (change.after ?? _initial(change.key)).map(mapValue),
          result._globals[change.key] ?? result._initial(change.key),
        ),
      );
    }
    for (final change in after._objects.differences(before._objects)) {
      final next = change.after;
      if (next == null) continue; // Projection is not an object destruction.
      final object = mapObject(change.key);
      final prior = change.before;
      var current = result._objects[object];
      if (prior == null || current == null) {
        if (preservesInputSources) continue;
        result._allocate(object, next.map(mapValue));
        continue;
      }
      for (final slot in next.slots.differences(prior.slots)) {
        if (slot.after == null) {
          throw StateError('A summary cannot remove a declared storage slot.');
        }
        current = current!.withSlot(
          slot.key,
          preserve(slot.after!.map(mapValue), current.slots[slot.key]),
        );
      }
      if (preservesInputSources) {
        result._objects = result._objects.withEntry(object, current!);
        continue;
      }
      current = current!.withFlags(summary: next.summary && !prior.summary);
      if (!_sameCaptures(next.captures, prior.captures)) {
        current = _ObjectState._(
          current.slots,
          next.captures == null
              ? null
              : List.unmodifiable(next.captures!.map(mapValue)),
          current.summary,
          current.memory,
        );
      }
      if (next.memory != prior.memory) {
        current = current.withMemory(next.memory?.map(mapValue));
      }
      result._objects = result._objects.withEntry(object, current);
    }
    if (!preservesInputSources && after._escaped != before._escaped) {
      result._escaped = result._escaped.join(mapValue(after._escaped));
    }
    return result;
  }

  void _setGlobal(GlobalVariable global, _Slot slot) {
    _globals = slot == _initial(global)
        ? _globals.withoutKey(global)
        : _globals.withEntry(global, slot);
  }

  /// Whether this state contains storage for the analysis allocation.
  bool containsObject(FlowObject object) => _objects[object] != null;

  /// Captures of this allocation, preserving shared cell identities.
  List<FlowValue>? capturesOf(FlowObject object) => _objects[object]?.captures;

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
  /// The caller supplies previously escaped roots and global access explicitly.
  void invalidate(Iterable<FlowValue> roots, {bool globals = false}) {
    final reachable = exposedFrom([
      ...roots,
      if (globals)
        for (final slot in _globals.values) ...[slot.value, slot.initializer],
    ]);
    final raw = reachableValues([for (final root in roots) root.references]);
    for (final object in reachable.objects) {
      final state = _objects[object];
      if (state == null) continue;
      var next = state;
      for (final entry in state.slots.entries) {
        final key = entry.key;
        final type = key is InstanceField
            ? key.typeFor(object.type as ClassType)
            : (object.type as CellType).content;
        final isFinal = key is InstanceField
            ? key.isFinal
            : (object.type as CellType).isFinal;
        next = next.withSlot(
          key,
          entry.value.invalidate(
            type,
            isFinal: isFinal && !raw.objects.contains(object),
          ),
        );
      }
      next = next.withMemory(state.memory?.invalidate());
      _objects = _objects.withEntry(object, next);
    }
    if (globals) {
      for (final global in _declaredGlobals) {
        final slot = _globals[global] ?? _initial(global);
        _setGlobal(
          global,
          slot.invalidate(global.type, isFinal: global.isFinal),
        );
      }
    }
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
  }) {
    if (arguments.any((value) => value.isBottom)) return _unreachable;
    final type = object.type as ClassType;
    final next = copy();
    final slots = <Object, _Slot>{};
    for (ClassType? view = type; view != null; view = view.superclass) {
      for (final field in _class(view)?.fields ?? <InstanceField>[]) {
        slots[field] = !field.isLate && field.typeFor(type).mayBeNull
            ? _Slot.bound(_null)
            : const _Slot.unbound();
      }
    }
    next._allocate(object, _ObjectState(slots, summary: repeated));
    final value = FlowValue.object(object);
    final result = invoke(initializer, [value, ...arguments], next);
    return FlowResult(
      value: result.normal == null ? const .bottom() : value,
      normal: result.normal,
      exceptional: result.exceptional,
      exception: result.exception,
      stackTrace: result.stackTrace,
      effects: const {Effect.allocates},
    );
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
    switch (operation) {
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
        final start = memoryLayout?.objectLayout(object.type as ClassType).size;
        final valid =
            length != null &&
            length >= 0 &&
            (start == null || length <= 0x7fffffffffffffff - start);
        final next = copy()
          .._allocate(
            object,
            _ObjectState(
              {},
              summary: repeated,
              memory: start == null
                  ? null
                  : FlowMemory(start, valid ? length : null),
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
        final address = _objectAddress(operands.first, operands[1]);
        final next = _writeNative(
          address,
          _referenceSlot(operands.first, operands[1])
              ? ObjectHeader.alignment
              : null,
          operands.last,
          (memory, offset) => memory.writeReference(offset, operands.last),
        );
        return _withEffects(_normal(_null, next), const {Effect.writesStorage});
      case LoadNative(nativeType: final NativeTypeRef nativeType) ||
          LoadObjectData(nativeType: final NativeTypeRef nativeType):
        if (operands.any((value) => value.isBottom)) return _unreachable;
        final input = operation is LoadObjectData
            ? _objectAddress(operands.first, operands.last)
            : operands.single;
        var value = const FlowValue.bottom();
        final layout = memoryLayout?.nativeLayout;
        final size = layout?.of(nativeType).size;
        for (final address in input.addresses) {
          final memory = _memoryOf(address.base);
          value = value.join(
            layout != null &&
                    size != null &&
                    address.offsets != null &&
                    memory != null &&
                    memory.containsRange(address.offsets!, size)
                ? memory.readRange(address.offsets!, nativeType, layout)
                : FlowValue.unknown(resultType)
                      .withReferences([address.reference]),
          );
        }
        if (input.addresses.isEmpty ||
            input.unknownTypes.isNotEmpty ||
            input.constants.isNotEmpty) {
          value = value.join(
            FlowValue.unknown(resultType).withReferences([input.references]),
          );
        }
        return _withEffects(_normal(value, copy()), const {
          Effect.readsStorage,
        });
      case StoreNative(nativeType: final NativeTypeRef nativeType) ||
          StoreObjectData(nativeType: final NativeTypeRef nativeType):
        if (operands.any((v) => v.isBottom)) return _unreachable;
        final address = operation is StoreObjectData
            ? _objectAddress(operands.first, operands[1])
            : operands.first;
        final layout = memoryLayout?.nativeLayout;
        final size = layout?.of(nativeType).size;
        final next = _writeNative(
          address,
          size,
          operands.last,
          (memory, offset) =>
              memory.write(offset, nativeType, operands.last, layout!),
        );
        return _withEffects(_normal(_null, next), const {Effect.writesStorage});
      case CopyNative(:final nativeType):
        if (operands.any((v) => v.isBottom)) return _unreachable;
        final size = memoryLayout?.nativeLayout.of(nativeType).size;
        if (size == 0) return _normal(_null, copy());
        final source = operands.last;
        final next = _writeNative(operands.first, size, source.references, (
          memory,
          offset,
        ) {
          FlowMemory? result;
          for (final address in source.addresses) {
            final from = _memoryOf(address.base);
            final copied = from != null && address.offset != null
                ? memory.copyFrom(offset, from, address.offset!, size!)
                : memory.forget(offset, size!, retained: source.references);
            result = result == null ? copied : result.join(copied);
          }
          if (result == null ||
              source.unknownTypes.isNotEmpty ||
              source.constants.isNotEmpty) {
            result = memory.forget(offset, size!, retained: source.references);
          }
          return result;
        });
        return _withEffects(_normal(_null, next), const {
          Effect.readsStorage,
          Effect.writesStorage,
        });
      case Construct(:final initializer):
        return construct(
          allocate(operation),
          initializer,
          operands,
          repeated: repeated,
          invoke: invoke,
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
      case StoreField(:final field):
        return _writeObjects(operands.first, field, operands.last);
      default:
        return null;
    }
  }

  FlowValue _objectAddress(FlowValue owner, FlowValue offset) {
    var value = const FlowValue.bottom();
    for (final base in <Object>[...owner.objects, ...owner.constants]) {
      value = value.join(
        FlowValue.address(FlowAddress.ranged(base, offset.integers)),
      );
    }
    if (owner.unknownTypes.isNotEmpty || value.isBottom) {
      value = value.join(FlowValue.unknown(.integer).withReferences([owner]));
    }
    return value;
  }

  FlowMemory? _memoryOf(Object base) {
    if (base is FlowObject) return _objects[base]?.memory;
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
    final bases = <Object>[...owner.objects, ...owner.constants];
    if (bases.isEmpty || owner.unknownTypes.isNotEmpty || offsets == null) {
      return false;
    }
    return offsets.zeroBits >= ObjectHeader.alignment.bitLength - 1 &&
        bases.every((base) {
          final type = switch (base) {
            FlowObject(:final type) || ObjectConstant(:final type) => type,
            _ => null,
          };
          return type is ClassType &&
              memoryLayout?.objectLayout(type).tracesPayload == true &&
              (_memoryOf(base)
                      ?.containsRange(offsets, ObjectHeader.alignment) ??
                  false);
        });
  }

  FlowValue? _readReference(FlowValue owner, FlowValue offset) {
    if (!_referenceSlot(owner, offset)) return null;
    var value = const FlowValue.bottom();
    for (final base in <Object>[...owner.objects, ...owner.constants]) {
      final read = _memoryOf(base)!.readReferenceRange(offset.integers!);
      if (read == null) return null;
      value = value.join(read);
    }
    return value;
  }

  FlowState _writeNative(
    FlowValue address,
    int? size,
    FlowValue stored,
    FlowMemory Function(FlowMemory, int) write,
  ) {
    final next = copy();
    final known =
        size != null &&
        address.addresses.isNotEmpty &&
        address.constants.isEmpty &&
        address.unknownTypes.isEmpty &&
        address.addresses.every(
          (a) =>
              a.base is FlowObject &&
              a.offsets != null &&
              (_objects[a.base as FlowObject]?.memory?.containsRange(
                    a.offsets!,
                    size,
                  ) ??
                  false),
        );
    if (!known) {
      // An unbounded offset can reach other allocations, not just its base.
      next._invalidateRaw();
      next.escape([stored]);
      return next;
    }
    final strong = address.addresses.length == 1;
    for (final pointer in address.addresses) {
      final object = pointer.base as FlowObject;
      final state = _objects[object]!;
      final offsets = pointer.offsets!;
      final memory = offsets.constant != null
          ? write(state.memory!, offsets.constant!)
          : state.memory!.forget(
              offsets.lower,
              offsets.upper - offsets.lower + size,
              retained: stored,
            );
      next._objects = next._objects.withEntry(
        object,
        next._objects[object]!.withMemory(
          strong && !state.summary
              ? memory
              : next._objects[object]!.memory!.join(memory),
        ),
      );
    }
    next.escape(const []);
    return next;
  }

  void _invalidateRaw() {
    for (final global in _declaredGlobals) {
      _setGlobal(
        global,
        (_globals[global] ?? _initial(global)).invalidate(
          global.type,
          isFinal: false,
        ),
      );
    }
    _objects = _objects.mapValues((object, state) {
      final slots = state.slots.mapValues((key, slot) {
        final type = key is InstanceField
            ? key.typeFor(object.type as ClassType)
            : (object.type as CellType).content;
        return slot.invalidate(type, isFinal: false);
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
      final type = field?.typeFor(object.type as ClassType) ?? cell!.content;
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
      if (key is InstanceField && constant is ObjectConstant) {
        final value = constant.fields[key];
        if (value != null) {
          var read = _normal(FlowValue.constant(value), copy());
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
          .unknown(bound),
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
    var result = _normal(FlowValue.unknown(type), copy());
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
            value: committed.normal == null ? const .bottom() : .unknown(type),
            normal: committed.normal,
            exceptional: committed.exceptional,
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
        ),
      );
    } else if (field?.requiresReadCheck ?? false) {
      result = FlowResult(
        value: result.value,
        normal: result.normal,
        exceptional: copy(),
      );
    }
    return _withEffects(result, const {Effect.readsStorage});
  }

  FlowResult _writeObjects(FlowValue receiver, Object key, FlowValue value) {
    if (value.isBottom) return _unreachable;
    var result = _unreachable;
    final unknownBounds = {
      ...receiver.unknownTypes,
      ...receiver.constants.map((value) => value.type),
    };
    for (final object in receiver.objects) {
      final field = key is InstanceField ? key : null;
      final cell = field == null ? object.type as CellType : null;
      if (_objects[object]?.slots[key] == null) {
        unknownBounds.add(object.type);
        continue;
      }
      result = _merge(
        result,
        _write(
          (object, key),
          value,
          field?.typeFor(object.type as ClassType) ?? cell!.content,
          isFinal: field == null
              ? cell!.isFinal
              : field.isLate && field.isFinal,
        ),
      );
    }
    if (unknownBounds.isNotEmpty) {
      final next = copy()..escape([value]);
      for (final object in next._objects.keys) {
        final state = next._objects[object]!;
        final slot = state.slots[key];
        if (slot == null ||
            !unknownBounds.any(
              (t) => object.type is ClassType
                  ? t.mayHaveInstance(object.type as ClassType)
                  : t.accepts(object.type),
            )) {
          continue;
        }
        final type = key is InstanceField
            ? key.typeFor(object.type as ClassType)
            : (object.type as CellType).content;
        final isFinal = key is InstanceField
            ? key.isLate && key.isFinal
            : (object.type as CellType).isFinal;
        if (isFinal && !slot.unbound) continue;
        final checked = value.check(type);
        if (!checked.value.isBottom) {
          next._objects = next._objects.withEntry(
            object,
            state.withSlot(key, slot.join(_Slot.bound(checked.value))),
          );
        }
      }
      result = _merge(
        result,
        FlowResult(
          value: _null,
          normal: next,
          exceptional: copy(),
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
      final bound = copy().._refine(location, _Slot.bound(slot.value));
      result = _normal(slot.value, bound);
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
          ),
        );
      } else {
        final initialized = initialize(unbound);
        var bound = FlowResult(
          value: const FlowValue.bottom(),
          normal: null as FlowState?,
          exceptional: initialized.exceptional,
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
    if (checked.value.isBottom) {
      return FlowResult(
        value: const .bottom(),
        normal: null,
        exceptional: exceptional,
        effects: const {Effect.readsStorage},
      );
    }
    final slot = _slot(location);
    if (isFinal && !slot.value.isBottom) {
      final bound = copy().._refine(location, _Slot.bound(slot.value));
      exceptional = _joinStates(exceptional, bound);
    }
    if (isFinal && !slot.unbound) {
      return FlowResult(
        value: const .bottom(),
        normal: null,
        exceptional: exceptional,
        effects: const {Effect.readsStorage},
      );
    }
    final next = copy();
    next._set(location, _Slot.bound(checked.value));
    return FlowResult(
      value: checked.value,
      normal: next,
      exceptional: exceptional,
      effects: {Effect.writesStorage, if (isFinal) Effect.readsStorage},
    );
  }

  void _allocate(FlowObject object, _ObjectState state) {
    final prior = _objects[object];
    // Existing input storage denotes an earlier allocation, not a solver revisit.
    _objects = _objects.withEntry(
      object,
      prior == null ? state : prior.join(state).withFlags(summary: true),
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
      return slot.unbound ? null : slot.value;
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
      value = value.join(slot.value);
    }
    for (final constant in receiver.constants) {
      if (constant is! ObjectConstant || !constant.fields.containsKey(key)) {
        return null;
      }
      value = value.join(.constant(constant.fields[key]!));
    }
    return value;
  }

  /// Bound field contents, without running an unbound initializer.
  FlowValue storedValue(FlowObject object, InstanceField field) =>
      _objects[object]?.slots[field]?.value ??
      FlowValue.unknown(field.typeFor(object.type as ClassType));

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

  FlowValue _reachable(Iterable<FlowValue> roots, {required bool expose}) {
    var result = const FlowValue.bottom();
    final pending = [for (final value in roots) (value, !expose)];
    final objects = <(FlowObject, bool)>{};
    final constants = <(Object, bool)>{};
    while (pending.isNotEmpty) {
      final (value, raw) = pending.removeLast();
      result = result.join(value);
      if (!value.references.isBottom) pending.add((value.references, true));
      for (final object in value.objects) {
        if (!objects.add((object, raw))) continue;
        final state = _objects[object];
        if (state == null) continue;
        if (state.memory case final memory?) {
          pending.add((memory.references, true));
        }
        if (raw) {
          pending.addAll([
            for (final capture in state.captures ?? const <FlowValue>[])
              (capture, raw),
          ]);
        }
        for (final slot in state.slots.values) {
          pending.add((slot.value, raw));
          if (raw && slot.unbound) pending.add((slot.initializer, raw));
        }
      }
      for (final constant in value.constants) {
        if (!constants.add((constant.structuralKey, raw))) continue;
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
    return result;
  }
}

final _cell = Object();
final _null = FlowValue.constant(const Constant.nullValue());
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
  exception: left.exception.join(right.exception),
  stackTrace: left.stackTrace.join(right.stackTrace),
  effects: Set.unmodifiable({...left.effects, ...right.effects}),
);

FlowResult _withEffects(FlowResult result, Set<Effect> effects) => FlowResult(
  value: result.value,
  normal: result.normal,
  exceptional: result.exceptional,
  exception: result.exception,
  stackTrace: result.stackTrace,
  effects: Set.unmodifiable({...result.effects, ...effects}),
);

FlowResult _checkedRead(FlowResult result, ValueType type) {
  if (result.normal == null) return result;
  final checked = result.value.check(type);
  return _merge(
    FlowResult(
      value: checked.value,
      normal: checked.value.isBottom ? null : result.normal,
      exceptional: result.exceptional,
      exception: result.exception,
      stackTrace: result.stackTrace,
      effects: result.effects,
    ),
    checked.mayFail ? FlowResult(exceptional: result.normal) : _unreachable,
  );
}

final class _Slot {
  final FlowValue value;
  final bool unbound;
  final FlowValue initializer;

  const new unbound({this.initializer = const .bottom()})
    : value = const .bottom(),
      unbound = true;
  const new bound(this.value) : unbound = false, initializer = const .bottom();
  new unknown(ValueType type)
    : value = .unknown(type),
      unbound = true,
      initializer = .unknown(FunctionType(type, []));
  const new _(this.value, this.unbound, this.initializer);

  _Slot join(_Slot other, {bool widen = false}) => _Slot._(
    value.join(other.value, widen: widen),
    unbound || other.unbound,
    initializer.join(other.initializer, widen: widen),
  );

  _Slot map(FlowValue Function(FlowValue) transform) {
    final mapped = _Slot._(transform(value), unbound, transform(initializer));
    return mapped == this ? this : mapped;
  }

  _Slot invalidate(ValueType type, {required bool isFinal}) =>
      isFinal && !unbound
      ? this
      : _Slot._(value.join(.unknown(type)), unbound, initializer);

  @override
  bool operator ==(Object other) =>
      other is _Slot &&
      other.value == value &&
      other.unbound == unbound &&
      other.initializer == initializer;
  @override
  int get hashCode => Object.hash(value, unbound, initializer);
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

  _ObjectState join(_ObjectState incoming, {bool widen = false}) {
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
        : memory!.join(incoming.memory!, widen: widen);
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
