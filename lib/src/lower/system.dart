import 'package:dartc/lir.dart';

/// The system functions that lowered code may call.
final systemFunctions = {
  'exit': LirSignature([.i64]),
  'fmod': LirSignature([.f64, .f64], .f64),

  /// write(descriptor, address, count).
  'write': LirSignature([.i64, .ptr, .i64], .i64),

  /// The address of the 32-bit error number.
  '__error': LirSignature([], .ptr),

  /// signal(number, handler).
  'signal': LirSignature([.i64, .i64], .i64),
};

/// Calls a function of [systemFunctions].
Call callSystem(String name, Iterable<LirValue> arguments) =>
    Call(name, systemFunctions[name]!, arguments);
