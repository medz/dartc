import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';

/// An indirect native call after Dart pointer objects have yielded raw addresses.
final class NativeInvocation(
  final Value address,
  final List<Value> arguments,
  final NativeSignature signature, {
  required final bool isLeaf,
}) extends Value {
  this
    : super(
        signature.result is NativePointerType
            ? ValueType.integer
            : FfiTypes.valueType(signature.result),
      );

  Iterable<Value> get inputs => [address, ...arguments];
}
