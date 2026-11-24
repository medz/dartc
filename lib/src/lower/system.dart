import 'package:dartc/lir.dart';

/// The system functions that lowered code may call.
final systemFunctions = {
  'exit': LirSignature([.i64]),
  'fmod': LirSignature([.f64, .f64], .f64),

  /// write(descriptor, address, count).
  'write': LirSignature([.i64, .ptr, .i64], .i64),

  /// gcvt(value, digits, address), the address.
  'gcvt': LirSignature([.f64, .i64, .ptr], .ptr),

  /// strtod(address, end).
  'strtod': LirSignature([.ptr, .ptr], .f64),

  for (final name in const [
    'sin',
    'cos',
    'tan',
    'asin',
    'acos',
    'atan',
    'exp',
    'log',
  ])
    name: LirSignature([.f64], .f64),
  'atan2': LirSignature([.f64, .f64], .f64),
  'pow': LirSignature([.f64, .f64], .f64),

  /// clock_gettime_nsec_np(clock), nanoseconds.
  'clock_gettime_nsec_np': LirSignature([.i64], .i64),

  /// localtime_r(seconds, result), the result.
  'localtime_r': LirSignature([.ptr, .ptr], .ptr),

  /// usleep(microseconds).
  'usleep': LirSignature([.i64]),

  /// 32 random bits; others are unknown.
  'arc4random': LirSignature([], .i64),

  /// The address of the 32-bit error number.
  '__error': LirSignature([], .ptr),

  /// mmap(address, bytes, protection, flags, descriptor, offset).
  'mmap': LirSignature(List.filled(6, .i64), .i64),

  /// munmap(address, bytes).
  'munmap': LirSignature([.i64, .i64], .i64),

  'pthread_self': LirSignature([], .i64),

  /// The end of a thread's stack, and its size.
  'pthread_get_stackaddr_np': LirSignature([.i64], .i64),
  'pthread_get_stacksize_np': LirSignature([.i64], .i64),

  /// signal(number, handler).
  'signal': LirSignature([.i64, .i64], .i64),
};

/// Calls a function of [systemFunctions].
Call callSystem(String name, Iterable<LirValue> arguments) =>
    Call(name, systemFunctions[name]!, arguments);
