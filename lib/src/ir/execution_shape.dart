import 'dart:ffi' show Bool, Double, Int64, UintPtr;

import 'package:dartc/interop.dart';

import 'block.dart';
import 'function.dart';
import 'signature.dart';
import 'type.dart';
import 'value.dart';

/// One C-compatible component and its precise managed-root interpretation.
final class ExecutionComponent(
  final NativeTypeRef nativeType, {
  final bool managedReference = false,
}) {
  this {
    if (!nativeType.isSized ||
        managedReference && nativeType != NativeScalarType(UintPtr)) {
      throw ArgumentError(
        'Execution components require sized storage; roots use UintPtr.',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ExecutionComponent &&
      nativeType == other.nativeType &&
      managedReference == other.managedReference;

  @override
  int get hashCode => Object.hash(nativeType, managedReference);
}

/// Physical value components, independent of Dart types and machine locations.
///
/// Components use the common native layout and calling foundation. Empty shapes
/// carry no result; a managed reference component is traced even when the value's
/// language type is a scalar. Nullable and generic storage policies are not fixed
/// by this type: a producer may select an aggregate and explicit adapters.
final class ExecutionShape(Iterable<ExecutionComponent> components) {
  final List<ExecutionComponent> components = .unmodifiable(components);

  static final empty = ExecutionShape([]);
  static final word = ExecutionShape([
    ExecutionComponent(NativeScalarType(Int64)),
  ]);
  static final floating = ExecutionShape([
    ExecutionComponent(NativeScalarType(Double)),
  ]);
  static final reference = ExecutionShape([
    ExecutionComponent(NativeScalarType(UintPtr), managedReference: true),
  ]);

  bool get hasReferences =>
      components.any((component) => component.managedReference);
  bool get isReference => this == reference;
  bool get isScalar => this == word || this == floating;

  /// Shared native storage for all components, with target offsets from NativeLayout.
  late final NativeTypeRef? storage = switch (components.length) {
    0 => null,
    1 => components.single.nativeType,
    _ => NativeCompoundType('ExecutionValue', [
      for (final (index, component) in components.indexed)
        NativeField('component$index', component.nativeType),
    ]),
  };

  @override
  bool operator ==(Object other) =>
      other is ExecutionShape &&
      components.length == other.components.length &&
      components.indexed.every(
        (entry) => entry.$2 == other.components[entry.$1],
      );

  @override
  int get hashCode => Object.hashAll(components);
}

/// Physical parameters and result of one actual execution entry.
final class ExecutionSignature(
  Iterable<ExecutionShape> parameters,
  final ExecutionShape result,
) {
  final List<ExecutionShape> parameters = .unmodifiable(parameters);

  @override
  bool operator ==(Object other) =>
      other is ExecutionSignature &&
      result == other.result &&
      parameters.length == other.parameters.length &&
      parameters.indexed.every(
        (entry) => entry.$2 == other.parameters[entry.$1],
      );

  @override
  int get hashCode => Object.hash(Object.hashAll(parameters), result);
}

/// An actual source closure capture slot, before storage lowering.
final class CaptureSlot(final FunctionTarget function, final int index) {
  this {
    if (index < 0 || index >= function.captures.length) {
      throw ArgumentError('Invalid closure capture slot.');
    }
  }
  @override
  bool operator ==(Object other) =>
      other is CaptureSlot &&
      function == other.function &&
      index == other.index;
  @override
  int get hashCode => Object.hash(function, index);
}

/// Body-owned SSA choices retained and rebound by every graph rewrite.
final class FunctionExecution(Map<Value, ExecutionShape> values) {
  final Map<Value, ExecutionShape> values = .unmodifiable(values);

  /// Rejects bindings to another function's SSA definitions.
  void checkValues(IrFunction function) {
    final owned = <Value>{
      for (final block in function.blocks) ...[
        ...block.parameters,
        ...block.instructions,
        if (block.end case Invoke(:final operation)) operation,
      ],
    };
    if (values.keys.any(
      (value) => value is Constant || !owned.contains(value),
    )) {
      throw ArgumentError('Execution choices require owned SSA values.');
    }
  }
}

/// The persistent physical authority for entries, shared slots and SSA values.
///
/// Semantic types remain on their declarations. An absent explicit choice uses
/// the single compatibility policy here; consumers must not independently infer
/// a different carrier from Value.type. Rewriters preserve entry/slot identities
/// and remap FunctionExecution SSA bindings to their actual rewritten values.
final class ExecutionShapes({
  Map<FunctionTarget, ExecutionSignature> entries = const {},
  Map<Object, ExecutionShape> slots = const {},
}) {
  final Map<FunctionTarget, ExecutionSignature> entries = .unmodifiable(
    entries,
  );
  final Map<Object, ExecutionShape> slots = .unmodifiable(slots);

  this {
    for (final entry in this.entries.entries) {
      if (entry.key.parameterTypes.length != entry.value.parameters.length) {
        throw ArgumentError(
          'Execution entry arity differs from its declaration.',
        );
      }
    }
    for (final entry in this.slots.entries) {
      if (entry.key case CellType(:final slotShape)
          when entry.value != slotShape) {
        throw ArgumentError(
          'A cell carrier cannot reinterpret its fixed slot.',
        );
      }
    }
    if (this.slots.keys.any(
      (slot) =>
          slot is! InstanceField &&
          slot is! GlobalVariable &&
          slot is! CellType &&
          slot is! CaptureSlot,
    )) {
      throw ArgumentError(
        'Execution storage requires an actual declared slot.',
      );
    }
  }

  static final defaults = ExecutionShapes();

  /// The compatibility policy for newly introduced, unbound values and slots.
  /// Dart void can carry a dynamic value; only an explicit empty shape erases it.
  static ExecutionShape forType(ValueType type) {
    if (!ValueType.never.accepts(type)) {
      if (ValueType.integer.accepts(type) || ValueType.boolean.accepts(type)) {
        return ExecutionShape.word;
      }
      if (ValueType.floating.accepts(type)) return ExecutionShape.floating;
    }
    return ExecutionShape.reference;
  }

  /// The native payload codec shared by scalar materialization and analysis.
  static NativeScalarType scalarStorageOf(ValueType type) {
    final shape = forType(type);
    if (!shape.isScalar) {
      throw ArgumentError('Scalar payload storage requires a scalar type.');
    }
    return ValueType.boolean.accepts(type)
        ? NativeScalarType(Bool)
        : shape.components.single.nativeType as NativeScalarType;
  }

  ExecutionSignature entryOf(FunctionTarget target) =>
      entries[target] ??
      ExecutionSignature([
        for (final (index, type) in target.parameterTypes.indexed)
          target.kind == .initializer && index == 0
              ? ExecutionShape.reference
              : target.kind == .closure &&
                    index > 0 &&
                    index <= target.captures.length
              ? slotOf(CaptureSlot(target, index - 1))
              : forType(type),
      ], forType(target.returnType));

  ExecutionShape slotOf(Object slot) => switch (slot) {
    CellType(:final slotShape) => slotShape,
    _ =>
      slots[slot] ??
          forType(switch (slot) {
            InstanceField(:final type) || GlobalVariable(:final type) => type,
            CaptureSlot(:final function, :final index) =>
              function.captures[index],
            _ => throw ArgumentError('Unknown execution slot.'),
          }),
  };

  /// The carrier of the actual producer, not merely its language type.
  ExecutionShape shapeOf(
    IrFunction? function,
    Value value, {
    Map<Value, ExecutionShape> values = const {},
  }) {
    if (values[value] case final shape?) return shape;
    if (function?.execution?.values[value] case final shape?) return shape;
    return producerShapeOf(function, value, values: values);
  }

  /// Derives the carrier from the producer before applying a binding for [value].
  /// Operand bindings, entry signatures, and storage layouts still apply.
  ExecutionShape producerShapeOf(
    IrFunction? function,
    Value value, {
    Map<Value, ExecutionShape> values = const {},
  }) {
    return switch (value) {
      MaterializeValue() ||
      MaterializedValue() ||
      ConstantCarrier() ||
      AllocatedObject() ||
      ManagedStorageAllocation() ||
      ReferenceFromAddress() ||
      ModuleObjectReference() ||
      CellReference() ||
      CallableReference() => ExecutionShape.reference,
      ProjectValue(:final shape) => shape,
      TypeView(:final operand) ||
      UncheckedCast(:final operand) ||
      TypeCast(:final operand) ||
      NullCheck(:final operand) => shapeOf(function, operand, values: values),
      TestedValue(:final test) => shapeOf(
        function,
        test.operand,
        values: values,
      ),
      DirectCall(:final target) => entryOf(target).result,
      FunctionCall(entryBinding: final binding?) ||
      DynamicDispatch(
        entryBinding: final binding?,
      ) => binding.shape.execution.result,
      InstanceCall(entryBinding: final binding?) => binding.execution.result,
      BindMethod(entryBinding: final binding?) => binding.execution.result,
      LoadField(:final field) => slotOf(field),
      LoadGlobal(:final global) => slotOf(global),
      ReadCell(:final cell) => slotOf(cell.type),
      ReadFunctionEnvironment(:final source, capture: final int index) =>
        slotOf(CaptureSlot(source, index)),
      BlockParameter()
          when function != null && function.entry.parameters.contains(value) =>
        entryOf(function.target)
            .parameters[function.entry.parameters.indexOf(value)],
      _ => forType(value.type),
    };
  }

  /// Required carriers at the operation's actual operand positions.
  List<ExecutionShape> inputShapesOf(
    IrFunction? function,
    Instruction operation, {
    Map<Value, ExecutionShape> values = const {},
  }) {
    final ref = ExecutionShape.reference, word = ExecutionShape.word;
    return switch (operation) {
      MaterializeValue(:final value) => [forType(value.type)],
      MaterializedValue(:final value) => [forType(value.type), ref],
      ProjectValue() => [ref],
      ConstantCarrier(:final value) => [forType(value.type)],
      TypeTest(:final operand) ||
      ObjectRuntimeType(
        :final operand,
        direct: false,
      ) => [shapeOf(function, operand, values: values)],
      TypeView(:final operand) ||
      UncheckedCast(:final operand) ||
      TypeCast(:final operand) ||
      NullCheck(:final operand) => [shapeOf(function, operand, values: values)],
      KeepAlive(:final value) => [shapeOf(function, value, values: values)],
      DirectCall(:final target) => entryOf(target).parameters,
      BindMethod(entryBinding: final binding?) => binding.execution.parameters,
      InstanceCall(:final named, entryBinding: final binding?) => [
        ...binding.execution.parameters.take(1 + binding.positionalCount),
        for (final name in named.keys)
          binding.execution.parameters[1 + binding.positionalCount + binding.names.indexOf(name)],
        ...binding.execution.parameters.skip(1 + binding.positionalCount + binding.names.length),
      ],
      FunctionCall(:final named, entryBinding: final binding?) ||
      DynamicDispatch(:final named, entryBinding: final binding?) => [
        ...binding.shape.execution.parameters.take(
          1 + binding.shape.positional.length,
        ),
        for (final name in named.keys)
          binding.shape.execution.parameters[1 +
              binding.shape.positional.length +
              binding.shape.named.keys.toList().indexOf(name)],
      ],
      Construct(:final initializer, :final typeDescriptor) => [
        ...entryOf(initializer).parameters.skip(1),
        if (typeDescriptor != null) ref,
      ],
      InitializeObject(:final initializer) => [
        ref,
        ...entryOf(initializer).parameters.skip(1),
      ],
      StoreField(:final field) => [ref, slotOf(field)],
      LoadField() => [ref],
      StoreGlobal(:final global) => [slotOf(global)],
      WriteCell(:final cell) => [ref, slotOf(cell.type)],
      ReadCell() || CopyCell() => [ref],
      NewCell(:final initial, :final initializer) => [
        if (initial != null) slotOf(operation.type),
        if (initializer != null) ref,
      ],
      ReferenceAddress() => [ref],
      LoadObjectData() || LoadObjectReference() => [ref, word],
      StoreObjectReference() => [ref, word, ref],
      StoreObjectData(:final value) => [ref, word, forType(value.type)],
      MakeClosure(:final target) => [
        for (var i = 0; i < target.captures.length; i++)
          slotOf(CaptureSlot(target, i)),
      ],
      _ => operation.inputs.map((value) => forType(value.type)).toList(),
    };
  }

  /// Rejects implicit physical conversions after representation normalization.
  /// Optional predicates check only a transient demand slice. Final execution
  /// closure must call this without predicates to verify the complete body.
  void verify(
    IrFunction function, {
    bool Function(Instruction)? operationIncluded,
    bool Function(Jump)? edgeIncluded,
    bool Function(Block)? endIncluded,
  }) {
    final actualShapes = <Value, ExecutionShape>{
      for (final block in function.blocks)
        for (final value in <Value>[
          ...block.parameters,
          ...block.instructions,
          if (block.end case Invoke(:final operation)) operation,
        ])
          value: shapeOf(function, value),
    };
    void transfer(Value value, ExecutionShape destination) {
      if (shapeOf(function, value) != destination) {
        throw StateError(
          'Unnormalized execution transfer in ${function.target.name}.',
        );
      }
    }

    for (final (index, parameter) in function.entry.parameters.indexed) {
      transfer(parameter, entryOf(function.target).parameters[index]);
    }
    for (final block in function.blocks) {
      for (final operation in [
        ...block.instructions,
        if (block.end case Invoke(:final operation)) operation,
      ]) {
        if (operationIncluded != null && !operationIncluded(operation)) {
          continue;
        }
        final intrinsic = producerShapeOf(null, operation, values: actualShapes);
        if (shapeOf(function, operation) != intrinsic) {
          throw StateError(
            'An execution binding contradicts its actual producer.',
          );
        }
        final inputs = operation.inputs.toList();
        final expected = inputShapesOf(function, operation);
        if (inputs.length != expected.length) {
          throw StateError(
            'Execution operand arity differs from the operation.',
          );
        }
        for (final (index, input) in inputs.indexed) {
          transfer(input, expected[index]);
        }
      }
      for (final edge in block.successors) {
        if (edgeIncluded != null && !edgeIncluded(edge)) continue;
        for (final (index, argument) in edge.arguments.indexed) {
          transfer(argument, shapeOf(function, edge.target.parameters[index]));
        }
      }
      if (endIncluded != null && !endIncluded(block)) continue;
      switch (block.end) {
        case Branch(:final condition):
          transfer(condition, ExecutionShape.word);
        case Return(:final value):
          transfer(
            value ?? const Constant.nullValue(),
            entryOf(function.target).result,
          );
        case Throw(:final exception, :final stackTrace):
          transfer(exception, ExecutionShape.reference);
          if (stackTrace != null) {
            transfer(stackTrace, ExecutionShape.reference);
          }
        default:
          break;
      }
    }
  }
}
