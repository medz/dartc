/// An explicit native function signature with signed 64-bit values.
final class NativeSignature.int64(final int parameterCount) {
  this {
    if (parameterCount < 0) {
      throw ArgumentError.value(parameterCount, 'parameterCount');
    }
  }
}
