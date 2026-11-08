/// Implements the register boundary of native integer calls.
abstract interface class CallingConvention<R>() {
  /// The registers receiving required integer parameters, in source order.
  List<R> get parameters;

  /// The registers a callee may overwrite, excluding reserved scratch registers.
  List<R> get callerSaved;

  /// The register carrying an integer return value.
  R get result;

  /// Establishes a frame with [localBytes] bytes aligned to 16 bytes.
  void enterFrame(int localBytes);

  /// Restores a frame created with the same [localBytes], before returning.
  void leaveFrame(int localBytes);

  /// Returns [value] through the native integer result register.
  void returnValue(R value);
}
