import 'dart:ffi';

import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';

import 'heap_runtime.dart';

/// Provides ordinary IR bodies for allocation and initialization.
final class HeapPlan({final HeapRuntime? runtime}) {
  final _factories =
      <FunctionTarget, ({FunctionTarget? initializer, ClassType type})>{};
  final _boxes = <ValueType, FunctionTarget>{};
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

  bool allocates(Iterable<FunctionTarget> calls) =>
      calls.any(_factories.containsKey);

  /// Source initializers called by the retained allocation wrappers.
  Iterable<FunctionTarget> initializersFor(Iterable<FunctionTarget> calls) =>
      calls.map((target) => _factories[target]?.initializer).nonNulls;

  FunctionTarget box(ValueType type) => _boxes.putIfAbsent(type, () {
    final target = FunctionTarget(null, 'box${_boxes.length}', .object, [type]);
    _factories[target] = (initializer: null, type: type as ClassType);
    return target;
  });

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
  final _constructions = <FunctionTarget, IrFunction>{};

  /// Supplies a typed constructor bridge before target representation is erased.
  IrFunction construction(FunctionTarget initializer) =>
      _constructions.putIfAbsent(initializer, () {
        final type = initializer.owner!;
        final target = FunctionTarget(
          null,
          'construct${_constructions.length}',
          type,
          initializer.signature.parameters,
          typeParameters: type.typeParameters,
        );
        final entry = Block(target.parameterTypes);
        final object = _allocate(
          entry,
          type,
          type,
          entry.emit(ReifyType(type)),
          const Constant.integer(0),
        );
        entry.emit(InitializeObject(initializer, object, entry.parameters));
        entry.finish(Return(object));
        return IrFunction(target, [entry]);
      });

  /// Supplies the same payload bridge consumed by physical preparation.
  IrFunction payload(ClassType type) {
    final target = allocatePayload(type);
    return _functions.putIfAbsent(target, () => _build(target));
  }

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
    Value payload,
  ) {
    final context = _runtime.primitives.entries
        .singleWhere((entry) => entry.value == .context)
        .key;
    final address = entry.emit(
      DirectCall(allocate, [
        entry.emit(DirectCall(context, [])),
        entry.emit(ObjectDescriptorAddress(type)),
        CallFrameValue.stackPointer,
        CallFrameValue.returnAddress,
        payload,
      ]),
    );
    final object = entry.emit(
      resultType == type
          ? AllocatedObject(address, type, payload)
          : ReferenceFromAddress(address, resultType),
    );
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
    } else if (_boxes[type] == target) {
      entry.emit(
        StoreObjectData(
          object,
          const Constant.integer(ObjectHeader.fieldsOffset),
          NativeScalarType(
            type == ValueType.floating
                ? Double
                : type == ValueType.boolean
                ? Bool
                : Int64,
          ),
          entry.parameters.single,
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
          [...initializer.erasedParameterTypes.skip(1), TypeMetadata.type],
        );
        _factories[target] = (
          initializer: initializer,
          type: initializer.owner!,
        );
        return target;
      });
}
