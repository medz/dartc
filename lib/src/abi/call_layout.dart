import 'argument_location.dart';

/// Argument locations and call effects for a native signature.
///
/// Stack slots follow parameter order with their required alignment. The clobber
/// set covers represented 64-bit general and floating registers, not allocation
/// policy or unrepresented vector lanes.
/// [result] is absent for a `Void` result.
final class CallLayout<R>(
  Iterable<ArgumentLocation<R>> parameters,
  final ArgumentLocation<R>? result,
  Iterable<R> clobberedRegisters, {
  Map<R, int> registerInputs = const {},
}) {
  /// Parameter locations in source order.
  final List<ArgumentLocation<R>> parameters = .unmodifiable(parameters);

  /// The result register for a scalar call; aggregate callers use [result].
  R? get resultRegister => switch (result) {
    null => null,
    RegisterArgument(:final register) => register,
    _ => throw StateError('A native aggregate result has no single register.'),
  };

  /// Registers whose previous contents may be lost across the call.
  final Set<R> clobberedRegisters = .unmodifiable(clobberedRegisters);

  /// Implicit integer inputs set after argument staging, such as the SysV AL count.
  final Map<R, int> registerInputs = .unmodifiable(registerInputs);

  /// Whether integer condition flags may change across the call.
  bool get clobbersFlags => true;

  /// Argument storage at the caller's stack pointer, padded to 16 bytes.
  late final int stackBytes;

  this {
    final registers = <R>{};
    var bytes = 0;
    for (final location in this.parameters) {
      for (final register in location.registers) {
        if (!registers.add(register)) {
          throw ArgumentError('Repeated parameter register: $register');
        }
      }
      final storage = location is IndirectArgument<R>
          ? location.pointer
          : location;
      if (storage case StackArgument(
        :final offset,
        :final size,
        :final alignment,
      )) {
        if (offset != ((bytes + alignment - 1) & -alignment)) {
          throw ArgumentError('Expected consecutive stack arguments.');
        }
        bytes = offset + size;
      }
    }
    if (result is StackArgument<R> ||
        result is IndirectArgument<R> &&
            result!.registers.any(registers.contains)) {
      throw ArgumentError(
        'A hidden result address must have a distinct register.',
      );
    }
    if (this.registerInputs.keys.any(registers.contains)) {
      throw ArgumentError(
        'Implicit inputs must not overlap parameter registers.',
      );
    }
    if (!this.clobberedRegisters.containsAll([
      ...registers,
      ...this.registerInputs.keys,
      ...?result?.registers,
      if (result case IndirectArgument(:final returnedAddress?))
        returnedAddress,
    ])) {
      throw ArgumentError('Parameter and result registers must be clobbered.');
    }
    stackBytes = (bytes + 15) & ~15;
  }
}
