import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';

import 'heap_runtime.dart';
import 'value_carrier.dart';

/// Provides ordinary IR bodies for allocation and initialization.
final class HeapPlan({
  final HeapRuntime? runtime,
  final NativeData? managedContext,
}) {
  final _factories =
      <FunctionTarget, ({FunctionTarget? initializer, ClassType type})>{};
  final _initializers = <FunctionTarget, FunctionTarget>{};
  final _payloads = <ClassType, FunctionTarget>{};
  static final _invalid = FunctionTarget(null, 'invalid', .never, []);

  FunctionTarget get invalid =>
      runtime?.primitives.entries
          .where((entry) => entry.value == .fail)
          .firstOrNull
          ?.key ??
      _invalid;
  FunctionTarget get allocate => _runtime.allocate;
  FunctionTarget get release => _runtime.release;
  FunctionTarget get isOutOfMemory => _runtime.isOutOfMemory;
  FunctionTarget get runEvents => _runtime.runEvents;
  HeapRuntime get _runtime =>
      runtime ??
      (throw ArgumentError(
        'Managed allocation requires a Dart runtime program.',
      ));

  bool allocates(Iterable<FunctionTarget> calls) => calls.any(
    (target) => target == runtime?.allocate || _factories.containsKey(target),
  );

  /// Source initializers called by the retained allocation wrappers.
  Iterable<FunctionTarget> initializersFor(Iterable<FunctionTarget> calls) =>
      calls.map((target) => _factories[target]?.initializer).nonNulls;

  /// Allocates zeroed inline bytes after a class's fixed fields.
  FunctionTarget allocatePayload(ClassType type) =>
      _payloads.putIfAbsent(type, () {
        final target = FunctionTarget(
          null,
          'payload${_payloads.length}',
          type,
          [.integer],
        );
        _factories[target] = (initializer: null, type: type);
        return target;
      });

  void retain(Set<FunctionTarget> calls) =>
      _factories.removeWhere((target, _) => !calls.contains(target));

  Set<FunctionTarget> get primitives => {...?runtime?.primitives.keys, invalid};

  final _functions = <FunctionTarget, IrFunction>{};
  final _constructions = <(FunctionTarget, StorageView?), IrFunction>{};
  final _callableConstructions = <(CallableStorage, ValueType), IrFunction>{};

  /// Uses the shared allocator and initializer for a function's physical object.
  IrFunction callableConstruction(CallableStorage storage, ValueType type) =>
      _callableConstructions.putIfAbsent((storage, type), () {
        final initializer = storage.initializer!;
        final target = FunctionTarget(null, 'constructFunction', type, [
          ...initializer.signature.parameters, TypeMetadata.type,
        ], typeParameters: type.freeTypeParameters.toList());
        final entry = Block(target.parameterTypes);
        final object = _allocate(entry, storage.type, type,
            entry.parameters.last, const Constant.integer(0),
            callableStorage: storage);
        entry.emit(InitializeObject(initializer, object,
            entry.parameters.take(entry.parameters.length - 1)));
        entry.finish(Return(object));
        return IrFunction(target, [entry]);
      });

  /// Supplies a typed constructor bridge before target representation is erased.
  IrFunction construction(FunctionTarget initializer, {StorageView? storageView}) =>
      _constructions.putIfAbsent((initializer, storageView), () {
        final type = storageView?.storageType ?? initializer.owner!;
        final target = FunctionTarget(
          null,
          'construct${_constructions.length}',
          type,
          initializer.signatureFor(type).parameters,
          typeParameters: {...type.freeTypeParameters, ...?storageView?.freeTypeParameters},
        );
        final entry = Block(target.parameterTypes);
        final object = _allocate(
          entry,
          type,
          type,
          entry.emit(ReifyType(type)),
          const Constant.integer(0),
          storageView: storageView,
        );
        entry.emit(InitializeObject(initializer, object, entry.parameters));
        entry.finish(Return(object));
        return IrFunction(target, [entry]);
      });

  final _materializations = <ValueType, IrFunction>{};

  /// Exposes scalar storage, allocation and payload writes to the same program.
  IrFunction materialization(ValueType type) =>
      _materializations.putIfAbsent(type, () {
        final shape = ExecutionShapes.forType(type);
        if (!shape.isScalar) {
          throw ArgumentError('Materialization requires a scalar value.');
        }
        final scalar = shape == ExecutionShape.floating
            ? ValueType.floating
            : ValueType.boolean.accepts(type)
            ? ValueType.boolean
            : ValueType.integer;
        final target = FunctionTarget(null, 'materialize', type, [type],
            typeParameters: type.freeTypeParameters.toList());
        final entry = Block(target.parameterTypes);
        final value = entry.parameters.single;
        final backing = _allocate(entry, scalar, scalar,
            entry.emit(ReifyType(scalar)), const Constant.integer(0));
        final payload = value.type == scalar
            ? value : entry.emit(UncheckedCast(value, scalar));
        entry.emit(StoreObjectData(backing,
            const Constant.integer(ObjectHeader.fieldsOffset),
            ExecutionShapes.scalarStorageOf(type),
            payload));
        final result = entry.emit(MaterializedValue(value, backing));
        entry.finish(Return(result));
        return IrFunction(target, [entry],
            execution: FunctionExecution({result: ExecutionShape.reference}));
      });

  /// Reads the real current scalar payload from its managed representation.
  IrFunction projection(ValueType type, ExecutionShape shape) {
    if (!shape.isScalar) {
      throw ArgumentError('Projection requires a scalar destination.');
    }
    final target = FunctionTarget(null, 'project', type, [type],
        typeParameters: type.freeTypeParameters.toList());
    final entry = Block(target.parameterTypes);
    final value = entry.parameters.single;
    final payload = entry.emit(LoadObjectData(value,
        const Constant.integer(ObjectHeader.fieldsOffset),
        ExecutionShapes.scalarStorageOf(type)));
    final result = payload.type == type
        ? payload
        : entry.emit(UncheckedCast(payload, type));
    entry.finish(Return(result));
    return IrFunction(target, [entry], execution: FunctionExecution({
      value: ExecutionShape.reference,
      payload: shape,
      if (!identical(payload, result)) result: shape,
    }));
  }

  final _payloadBodies = <(ClassType, StorageView?), IrFunction>{};

  /// A typed payload implementation expanded at the allocation site.
  IrFunction payload(ClassType type, {StorageView? storageView}) =>
      _payloadBodies.putIfAbsent((type, storageView), () {
    final target = FunctionTarget(null, 'allocatePayload', type, [
      .integer,
    ], typeParameters: {...type.freeTypeParameters, ...?storageView?.freeTypeParameters});
    final entry = Block(target.parameterTypes);
    entry.finish(
      Return(
        _allocate(
          entry,
          type,
          type,
          entry.emit(ReifyType(type)),
          entry.parameters.single,
          storageView: storageView,
        ),
      ),
    );
    return IrFunction(target, [entry]);
  });

  /// Materializes retained allocation behavior before machine selection.
  Iterable<IrFunction> functions(Set<FunctionTarget> calls) {
    for (final entry in _factories.entries) {
      if (calls.contains(entry.key)) {
        _functions.putIfAbsent(entry.key, () => _build(entry.key));
      }
    }
    return _functions.values;
  }

  Value _allocate(
    Block entry,
    ClassType type,
    ValueType resultType,
    Value metadata,
    Value payload, {
    CallableStorage? callableStorage,
    StorageView? storageView,
  }) {
    final arguments = <Value>[
        entry.emit(
          managedContext != null
              ? NativeDataAddress(managedContext!)
              : switch (runtime?.context) {
                  final query? => DirectCall(query, []),
                  null => ReadNativeContext(),
                },
        ),
        entry.emit(ObjectDescriptorAddress(type)),
        CallFrameValue.stackPointer,
        CallFrameValue.returnAddress,
        payload,
    ];
    final Value object;
    if (storageView != null) {
      object = entry.emit(ManagedStorageAllocation(allocate, storageView, arguments));
    } else {
      final address = entry.emit(DirectCall(allocate, arguments));
      object = entry.emit(
        callableStorage != null
            ? AllocatedObject.callable(address, callableStorage, resultType)
            : resultType == type
            ? AllocatedObject(address, type, payload)
            : ReferenceFromAddress(address, resultType),
      );
    }
    entry.emit(
      StoreObjectReference(
        object,
        const Constant.integer(ObjectHeader.typeOffset),
        metadata,
      ),
    );
    return object;
  }

  IrFunction _build(FunctionTarget target) {
    final (:initializer, :type) = _factories[target]!;
    final entry = Block(target.parameterTypes);
    final object = _allocate(
      entry,
      type,
      initializer == null
          ? target.returnType
          : type.typeParameters.isEmpty
          ? type
          : ValueType.object,
      initializer == null ? entry.emit(ReifyType(type)) : entry.parameters.last,
      _payloads[type] == target
          ? entry.parameters.single
          : const Constant.integer(0),
    );
    if (initializer != null) {
      entry.emit(
        InitializeObject(
          initializer,
          object,
          entry.parameters.take(entry.parameters.length - 1),
        ),
      );
    }
    entry.finish(Return(object));
    return IrFunction(target, [entry]);
  }

  FunctionTarget constructorFor(FunctionTarget initializer) =>
      _initializers.putIfAbsent(initializer, () {
        final target = FunctionTarget(
          null,
          'construct${_initializers.length}',
          .object,
          [
            for (final type in initializer.parameterTypes.skip(1))
              valueCarrier(type).freeTypeParameters.isEmpty
                  ? valueCarrier(type)
                  : ValueType.object.nullable,
            TypeMetadata.type,
          ],
        );
        _factories[target] = (
          initializer: initializer,
          type: initializer.owner!,
        );
        return target;
      });
}
