import 'package:dartc/ir.dart';

/// A selected storage access whose receiver need not have the carrier's Dart type.
///
/// The receiver is a live, non-null reference. Required Dart checks precede this
/// access, which cannot allocate, call or throw.
sealed class StorageAccess(
  final InstanceField field,
  final Value receiver,
  super.type,
) extends Value {
  Iterable<Value> get inputs;
}

final class StorageRead(InstanceField field, Value receiver, {ValueType? type})
    extends StorageAccess {
  this : super(field, receiver, type ?? field.type);

  @override
  Iterable<Value> get inputs => [receiver];
}

final class StorageWrite(InstanceField field, Value receiver, final Value value)
    extends StorageAccess {
  this : super(field, receiver, .voidType);

  @override
  Iterable<Value> get inputs => [receiver, value];
}
