import 'dart:_heap/machine.dart' show load64, store64;
import 'dart:_heap/objects.dart' show localTime, realTime, steadyTime;

@patch
class DateTime {
  @patch
  static int _getCurrentMicros() => realTime() ~/ 1000;

  /// Where the system tells about the time [seconds] since 1970.
  static int _zoneAt(int seconds) {
    final buffer = outputBuffer();
    store64(buffer, seconds);
    localTime(buffer);
    return buffer + 48;
  }

  @patch
  static String _timeZoneNameForClampedSeconds(int secondsSinceEpoch) {
    var at = load64(_zoneAt(secondsSinceEpoch) + 8), name = '';
    for (var byte = load8(at); byte != 0; byte = load8(++at)) {
      name = name + String.fromCharCode(byte);
    }
    return name;
  }

  @patch
  static int _timeZoneOffsetInSecondsForClampedSeconds(int secondsSinceEpoch) =>
      load64(_zoneAt(secondsSinceEpoch));
}

@patch
class Stopwatch {
  @patch
  static int _now() => steadyTime();
  @patch
  static int _computeFrequency() => 1000000000;
}

@patch
class _Uri {
  @patch
  static bool get _isWindowsPlatform => false;
}
