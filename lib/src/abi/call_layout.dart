/// Register locations and call effects for an Int64 native signature.
///
/// Only register-passed Int64 signatures are currently supported. The clobber
/// set covers the represented general-purpose registers, not allocation policy
/// or unrepresented floating-point and vector registers.
final class CallLayout<R>(
  Iterable<R> parameters,
  final R result,
  Iterable<R> clobberedRegisters,
) {
  /// Parameter registers in source order.
  final List<R> parameters = .unmodifiable(parameters);

  /// Registers whose previous contents may be lost across the call.
  final Set<R> clobberedRegisters = .unmodifiable(clobberedRegisters);

  /// Whether integer condition flags may change across the call.
  bool get clobbersFlags => true;

  /// The argument storage required at the caller's stack pointer.
  int get stackBytes => 0;

  this {
    if (this.parameters.toSet().length != this.parameters.length ||
        !this.clobberedRegisters.containsAll([...this.parameters, result])) {
      throw ArgumentError(
        'Expected distinct parameters and clobbered parameter/result registers.',
      );
    }
  }
}
