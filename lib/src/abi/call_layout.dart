import 'package:dartc/interop.dart';

import 'argument_location.dart';

/// Argument locations and call effects for an Int64 native signature.
///
/// Stack words are consecutive in parameter order. The clobber set covers the
/// represented general-purpose registers, not allocation policy or
/// unrepresented floating-point and vector registers.
final class CallLayout<R>(
  Iterable<ArgumentLocation<R>> parameters,
  final R result,
  Iterable<R> clobberedRegisters,
) {
  /// Parameter locations in source order.
  final List<ArgumentLocation<R>> parameters = .unmodifiable(parameters);

  /// Registers whose previous contents may be lost across the call.
  final Set<R> clobberedRegisters = .unmodifiable(clobberedRegisters);

  /// Whether integer condition flags may change across the call.
  bool get clobbersFlags => true;

  /// Argument storage at the caller's stack pointer, padded to 16 bytes.
  late final int stackBytes;

  /// Assigns a register prefix followed by consecutive Int64 stack words.
  factory int64(
    NativeSignature signature,
    List<R> registers,
    R result,
    Iterable<R> clobberedRegisters,
  ) => .new(
    [
      for (var i = 0; i < signature.parameterCount; i++)
        i < registers.length
            ? RegisterArgument(registers[i])
            : StackArgument((i - registers.length) * 8),
    ],
    result,
    clobberedRegisters,
  );

  this {
    final registers = <R>{};
    var bytes = 0;
    for (final location in this.parameters) {
      switch (location) {
        case RegisterArgument(:final register):
          if (!registers.add(register)) {
            throw ArgumentError('Repeated parameter register: $register');
          }
        case StackArgument(:final offset):
          if (offset != bytes) {
            throw ArgumentError('Expected consecutive stack arguments.');
          }
          bytes += 8;
      }
    }
    if (!this.clobberedRegisters.containsAll([...registers, result])) {
      throw ArgumentError('Parameter and result registers must be clobbered.');
    }
    stackBytes = (bytes + 15) & ~15;
  }
}
