/// Implements the register boundary of native integer calls.
abstract interface class CallingConvention<R>() {
  /// The registers receiving required integer parameters, in source order.
  List<R> get parameters;

  /// The registers a callee may overwrite, excluding reserved scratch registers.
  List<R> get callerSaved;

  /// Returns [value] through the native integer result register.
  void returnValue(R value);
}
