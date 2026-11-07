import 'dart:typed_data';

/// Emits 64-bit integer leaf functions using the target's native register ABI.
///
/// Implementations emit instructions immediately. Callers allocate only from
/// [temporaries], preserve live operands, and reject stack arguments for now.
abstract interface class IntegerAbi<R>() {
  /// The registers receiving integer parameters, in source order.
  List<R> get parameters;

  /// The caller-saved registers available to a function containing no calls.
  List<R> get temporaries;

  /// Loads a signed 64-bit constant.
  void loadImmediate(R destination, int value);

  /// Adds operands with 64-bit wrapping semantics, allowing register aliasing.
  void add(R destination, R left, R right);

  /// Subtracts operands with 64-bit wrapping semantics, allowing register aliasing.
  void subtract(R destination, R left, R right);

  /// Returns [value] through the native integer result register.
  void returnValue(R value);

  /// Returns the generated code and resets the instruction buffer.
  Uint8List takeBytes();
}
