import 'dart:ffi';

import 'package:dartc/interop.dart';

import 'argument_location.dart';

/// Argument locations and call effects for a native scalar signature.
///
/// Stack words are consecutive in parameter order. The clobber set covers the
/// represented 64-bit general and floating registers, not allocation policy or
/// unrepresented vector lanes.
/// [result] is absent for a `Void` result.
final class CallLayout<R>(
  Iterable<ArgumentLocation<R>> parameters,
  final R? result,
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

  /// Assigns independent integer and double banks, then consecutive stack words.
  factory scalars(
    NativeSignature signature, {
    required List<R> general,
    required List<R> floating,
    required R generalResult,
    required R floatingResult,
    required Iterable<R> clobberedRegisters,
  }) {
    var integers = 0, doubles = 0, stack = 0;
    final parameters = <ArgumentLocation<R>>[];
    for (final type in signature.parameters) {
      final bank = type == Double ? floating : general;
      final index = type == Double ? doubles++ : integers++;
      parameters.add(
        index < bank.length
            ? RegisterArgument(bank[index])
            : StackArgument((stack++) * 8),
      );
    }
    return .new(
      parameters,
      signature.result == Void
          ? null
          : signature.result == Double
          ? floatingResult
          : generalResult,
      clobberedRegisters,
    );
  }

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
    if (!this.clobberedRegisters.containsAll([...registers, ?result])) {
      throw ArgumentError('Parameter and result registers must be clobbered.');
    }
    stackBytes = (bytes + 15) & ~15;
  }
}
