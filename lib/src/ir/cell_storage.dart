import 'execution_shape.dart';
import 'signature.dart';
import 'type.dart';
import 'storage_view.dart';

/// Persistent storage for a shared variable, independent of its source binder.
/// The physical payload carrier remains fixed after type substitution. Finality
/// changes the access protocol without duplicating the object layout.
final class CellStorage(
  final ClassType type,
  final InstanceField value,
  final InstanceField? bound,
  final FunctionTarget initializer,
  final ExecutionShape slotShape, {
  final InstanceField? thunk,
}) {
  Iterable<InstanceField> get fields => [value, ?bound, ?thunk];
  bool get isLate => thunk != null;
  ValueType get content => value.type;

  this {
    if (type.isAbstract ||
        type.typeParameters.isNotEmpty ||
        value.owner != type ||
        ExecutionShapes.forType(content) != slotShape ||
        slotShape.isReference && content != ValueType.object.nullable ||
        value.initiallyUnbound == isLate ||
        value.isFinal ||
        value.isLate ||
        initializer.kind != .initializer ||
        initializer.owner != type ||
        (bound != null) != isLate ||
        bound != null &&
            (bound!.owner != type ||
                bound!.type != .boolean ||
                bound!.isFinal ||
                bound!.isLate) ||
        thunk != null &&
            (thunk!.owner != type ||
                thunk!.type != FunctionType(content, []).nullable ||
                thunk!.isFinal ||
                thunk!.isLate)) {
      throw ArgumentError('Invalid typed cell storage declaration.');
    }
  }

  /// The exact class view required to grant this internal storage capability.
  ClassType backingOf(CellType cell) {
    if (cell.slotShape != slotShape ||
        cell.isLate != isLate ||
        !slotShape.isReference && !content.accepts(cell.content)) {
      throw ArgumentError('A cell view must preserve its declared storage.');
    }
    return type;
  }

  /// The invariant logical contract produced with this allocation.
  StorageView viewOf(CellType cell) => StorageView(backingOf(cell), cell, {
    value: isLate && slotShape.isReference
        ? cell.content.nullable
        : cell.content,
    if (bound != null) bound!: ValueType.boolean,
    if (thunk != null) thunk!: FunctionType(cell.content, []).nullable,
  });

  bool contains(CellType cell, ClassType backing) =>
      cell.slotShape == slotShape &&
      cell.isLate == isLate &&
      backing == type &&
      content.accepts(cell.content);
}
