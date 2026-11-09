import 'dart:ffi';

import 'native_type.dart';

/// An explicit function signature using supported `dart:ffi` types.
///
/// Parameters accept fixed-width integers, [Double] and pointers to those
/// integers; the result also accepts [Void]. Other types throw
/// [UnsupportedError]. No host layout is inferred.
final class NativeSignature(final Type result, Iterable<Type> parameters) {
  /// Parameter types in declaration order.
  final List<Type> parameters = .unmodifiable(parameters);

  this {
    for (final type in [if (result != Void) result, ...this.parameters]) {
      type.nativeSize;
    }
  }
}
