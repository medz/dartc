import 'dart:convert';
import 'dart:ffi';

import '../../lib/runtime/contracts.dart';

/// Reads Unix epoch microseconds from the system's real-time clock.
int currentTimeMicros() {
  final time = Struct.create<_Timespec>();
  if (_clockGettime(0, time.address) != 0) {
    throw StateError('Cannot read the system clock.');
  }
  return time.seconds * 1000000 + time.nanoseconds ~/ 1000;
}

/// Reads the local time zone's abbreviation at an SDK-clamped Unix instant.
String timeZoneName(int secondsSinceEpoch) =>
    _withLocalTime(secondsSinceEpoch, (time) {
      final bytes = <int>[];
      for (var i = 0; time.zone[i] != 0; i++) {
        bytes.add(time.zone[i]);
      }
      return utf8.decode(bytes);
    });

/// Reads local time minus UTC, including the instant's daylight-saving offset.
int timeZoneOffsetInSeconds(int secondsSinceEpoch) =>
    _withLocalTime(secondsSinceEpoch, (time) => time.offset);

T _withLocalTime<T>(int seconds, T Function(_LocalTime) read) {
  // localtime_r may load zone data or take a lock, so its storage is not borrowed.
  final storage = _malloc(sizeOf<Long>() + sizeOf<_LocalTime>());
  if (storage == nullptr) throw const OutOfMemoryError();
  try {
    final input = storage.cast<Long>()..value = seconds;
    final output = (storage + sizeOf<Long>()).cast<_LocalTime>();
    if (_localtime(input, output) == nullptr) {
      throw StateError('Cannot read the local time zone.');
    }
    return read(output.ref);
  } finally {
    _free(storage);
  }
}

final class _Timespec() extends Struct {
  @Long()
  external int seconds;
  @Long()
  external int nanoseconds;
}

final class _LocalTime() extends Struct {
  @Array(9)
  external Array<Int> calendar;
  @Long()
  external int offset;
  external Pointer<Uint8> zone;
}

@SystemNative()
@Native<Int Function(Int, Pointer<_Timespec>)>(
  symbol: 'clock_gettime',
  isLeaf: true,
)
external int _clockGettime(int clock, Pointer<_Timespec> output);

@SystemNative()
@Native<Pointer<_LocalTime> Function(Pointer<Long>, Pointer<_LocalTime>)>(
  symbol: 'localtime_r',
)
external Pointer<_LocalTime> _localtime(
  Pointer<Long> seconds,
  Pointer<_LocalTime> output,
);

@SystemNative()
@Native<Pointer<Uint8> Function(Size)>(symbol: 'malloc')
external Pointer<Uint8> _malloc(int bytes);

@SystemNative()
@Native<Void Function(Pointer<Uint8>)>(symbol: 'free')
external void _free(Pointer<Uint8> storage);
