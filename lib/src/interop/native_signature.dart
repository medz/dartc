import 'dart:ffi';

/// An explicit function signature using supported `dart:ffi` types.
///
/// Parameters accept [Int64] and `Pointer<Int64>`; the result also accepts
/// [Void]. Other types throw [UnsupportedError]. No host layout is inferred.
final class NativeSignature(final Type result, Iterable<Type> parameters) {
  /// Parameter types in declaration order.
  final List<Type> parameters = .unmodifiable(parameters);

  this {
    for (final type in [if (result != Void) result, ...this.parameters]) {
      if (type != Int64 && type != Pointer<Int64>) {
        throw UnsupportedError('Native signature type: $type');
      }
    }
  }
}
