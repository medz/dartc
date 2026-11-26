import 'package:dartc/lir.dart';
import 'package:dartc/native.dart';

import 'system.dart';

/// Memory for what the system tells, until the next question.
const systemBufferSymbol = '.system', systemBufferBytes = 96;

/// How numbers are written with all the digits asked for.
const _formatSymbol = '.format', _format = '%.*g\x00';

/// What systems do in different ways.
sealed class SystemCalls() {
  factory of(OperatingSystem system) => switch (system) {
    .macos => MacosCalls(),
    .linux => LinuxCalls(),
  };

  bool _usesBuffer = false, _usesFormat = false;

  /// What is used.
  List<LirData> get data => [
    if (_usesBuffer)
      LirData(
        systemBufferSymbol,
        List.filled(systemBufferBytes, 0),
        writable: true,
        isolated: true,
      ),
    if (_usesFormat) LirData(_formatSymbol, _format.codeUnits),
  ];

  /// Nanoseconds since 1970, or since some time that never changes.
  LirValue realTime(LirBlock block);
  LirValue steadyTime(LirBlock block);

  /// 32 random bits; others are unknown.
  LirValue randomBits(LirBlock block);

  /// Writes [value] with [digits] at most to [address], and a 0 after it. There
  /// are [size] bytes.
  void formatDouble(
    LirBlock block,
    LirValue value,
    LirValue digits,
    LirValue address,
    int size,
  );

  /// The address of the 32-bit number of the last error.
  LirValue errorAddress(LirBlock block);

  /// What makes memory private, and not that of a file.
  int get anonymousMemory;

  /// The lowest address of the stack.
  LirValue stackStart(LirBlock block);

  /// What locks start with, and what waits for them.
  int get mutexSignature;
  int get conditionSignature;

  /// Waits for [condition] for some [microseconds] at most. There is memory for
  /// two words at [time].
  void waitFor(
    LirBlock block,
    LirValue condition,
    LirValue mutex,
    LirValue microseconds,
    LirValue time,
  );

  LirValue _buffer(LirBlock block, int offset) {
    _usesBuffer = true;
    final start = block.add(SymbolAddress(systemBufferSymbol));
    return block.add(PtrAdd(start, block.add(ConstInt(offset))));
  }

  /// Stores [microseconds] at [time] as seconds and nanoseconds.
  static void _storeTime(LirBlock block, LirValue microseconds, LirValue time) {
    final million = block.add(ConstInt(1000000));
    final seconds = block.add(IntBinary(.div, microseconds, million));
    final rest = block.add(IntBinary(.rem, microseconds, million));
    final nanoseconds = block.add(
      IntBinary(.mul, rest, block.add(ConstInt(1000))),
    );
    block
      ..add(Store(.i64, time, seconds))
      ..add(Store(.i64, time, nanoseconds, offset: 8));
  }
}

final class MacosCalls() extends SystemCalls {
  @override
  LirValue realTime(LirBlock block) => _time(block, 0);

  @override
  LirValue steadyTime(LirBlock block) => _time(block, 8);

  static LirValue _time(LirBlock block, int clock) => block.add(
    callSystem('clock_gettime_nsec_np', [block.add(ConstInt(clock))]),
  );

  @override
  LirValue randomBits(LirBlock block) =>
      block.add(callSystem('arc4random', []));

  @override
  void formatDouble(
    LirBlock block,
    LirValue value,
    LirValue digits,
    LirValue address,
    int size,
  ) => block.add(callSystem('gcvt', [value, digits, address]));

  @override
  LirValue errorAddress(LirBlock block) => block.add(callSystem('__error', []));

  @override
  int get anonymousMemory => 0x1002;

  @override
  LirValue stackStart(LirBlock block) {
    final thread = block.add(callSystem('pthread_self', []));
    final end = block.add(callSystem('pthread_get_stackaddr_np', [thread]));
    final size = block.add(callSystem('pthread_get_stacksize_np', [thread]));
    return block.add(IntBinary(.sub, end, size));
  }

  @override
  int get mutexSignature => 0x32aaaba7;

  @override
  int get conditionSignature => 0x3cb0b1bb;

  @override
  void waitFor(
    LirBlock block,
    LirValue condition,
    LirValue mutex,
    LirValue microseconds,
    LirValue time,
  ) {
    SystemCalls._storeTime(block, microseconds, time);
    block.add(
      callSystem('pthread_cond_timedwait_relative_np', [
        condition,
        mutex,
        time,
      ]),
    );
  }
}

final class LinuxCalls() extends SystemCalls {
  static const _realClock = 0, _steadyClock = 1;

  @override
  LirValue realTime(LirBlock block) => _time(block, _realClock);

  @override
  LirValue steadyTime(LirBlock block) => _time(block, _steadyClock);

  LirValue _time(LirBlock block, int clock) {
    final at = _buffer(block, 0);
    block.add(callSystem('clock_gettime', [block.add(ConstInt(clock)), at]));
    final seconds = block.add(Load(.i64, at));
    final billion = block.add(ConstInt(1000000000));
    final whole = block.add(IntBinary(.mul, seconds, billion));
    return block.add(
      IntBinary(.add, whole, block.add(Load(.i64, at, offset: 8))),
    );
  }

  @override
  LirValue randomBits(LirBlock block) {
    final at = _buffer(block, 0);
    block.add(
      callSystem('getrandom', [
        at,
        block.add(ConstInt(4)),
        block.add(ConstInt(0)),
      ]),
    );
    return block.add(Load(.u32, at));
  }

  @override
  void formatDouble(
    LirBlock block,
    LirValue value,
    LirValue digits,
    LirValue address,
    int size,
  ) {
    _usesFormat = true;
    block.add(
      callSystem('snprintf', [
        address,
        block.add(ConstInt(size)),
        block.add(SymbolAddress(_formatSymbol)),
        digits,
        value,
      ]),
    );
  }

  @override
  LirValue errorAddress(LirBlock block) =>
      block.add(callSystem('__errno_location', []));

  @override
  int get anonymousMemory => 0x22;

  @override
  LirValue stackStart(LirBlock block) {
    // After the attributes of the thread.
    const start = 72, size = 80;
    final attributes = _buffer(block, 0), result = _buffer(block, start);
    final thread = block.add(callSystem('pthread_self', []));
    block
      ..add(callSystem('pthread_getattr_np', [thread, attributes]))
      ..add(
        callSystem('pthread_attr_getstack', [
          attributes,
          result,
          _buffer(block, size),
        ]),
      )
      ..add(callSystem('pthread_attr_destroy', [attributes]));
    return block.add(Load(.i64, result));
  }

  @override
  int get mutexSignature => 0;

  @override
  int get conditionSignature => 0;

  @override
  void waitFor(
    LirBlock block,
    LirValue condition,
    LirValue mutex,
    LirValue microseconds,
    LirValue time,
  ) {
    // It is told until when to wait.
    final thousand = block.add(ConstInt(1000));
    final now = block.add(IntBinary(.div, realTime(block), thousand));
    final end = block.add(IntBinary(.add, now, microseconds));
    SystemCalls._storeTime(block, end, time);
    block.add(callSystem('pthread_cond_timedwait', [condition, mutex, time]));
  }
}
