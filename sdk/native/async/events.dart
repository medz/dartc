// What is done after `main`.
import 'dart:_heap/objects.dart' show pause, steadyTime;
import 'dart:_internal' show EventSource;

@patch
void _beforeScheduleMicrotaskCallback() {}

@patch
void _beforeSchedulePriorityCallback() {}

@patch
void Function() _microtaskEntryCallback(_AsyncCallbackEntry entry) =>
    entry.callback;

/// What runs the microtasks, if there are any.
void Function()? _immediate;

@patch
class _AsyncRun {
  @patch
  static void _scheduleImmediate(void callback()) {
    _immediate = callback;
  }
}

void _runImmediate() {
  final callback = _immediate;
  if (callback == null) return;
  _immediate = null;
  callback();
}

/// What else the program waits for.
final List<EventSource> _outside = [];

void _registerEvents(EventSource source) => _outside.add(source);

/// Runs all that is left, until there is nothing to wait for.
void _runEventLoop() {
  _runImmediate();
  while (_runOutside() || _EventTimer._runNext() || _waitOutside()) {}
  for (final source in _outside) {
    source.end();
  }
}

/// Handles what has happened outside, then the timers whose time has come.
/// Returns whether there was anything outside.
bool _runOutside() {
  var isAny = false;
  for (var i = 0; i < _outside.length; i++) {
    // What happens meanwhile comes after the timers.
    for (var rest = _outside[i].happened; rest > 0; rest--) {
      if (!_outside[i].runOne()) break;
      isAny = true;
      _runImmediate();
    }
  }
  if (isAny) _EventTimer._runNext(waits: false);
  return isAny;
}

/// Waits for something outside, if that has to be. Returns whether it did.
bool _waitOutside() {
  if (!_outside.any((source) => source.keepsAlive)) return false;
  _wait(-1);
  return true;
}

/// Waits for something to happen, for [microseconds] at most unless that is
/// negative.
void _wait(int microseconds) {
  // Only one can be waited for, and others are asked again soon.
  const soon = 2000;
  if (_outside.isEmpty) return pause(microseconds);
  final source = _outside.lastWhere(
    (source) => source.keepsAlive,
    orElse: () => _outside.last,
  );
  final isLong = microseconds < 0 || microseconds > soon;
  source.wait(_outside.length > 1 && isLong ? soon : microseconds);
}

@patch
class Timer {
  @patch
  static Timer _createTimer(Duration duration, void callback()) =>
      _EventTimer(duration.inMilliseconds, (_) {
        callback();
      }, false);

  @patch
  static Timer _createPeriodicTimer(
    Duration duration,
    void callback(Timer timer),
  ) => _EventTimer(duration.inMilliseconds, callback, true);
}

/// Timers, in the order in which the official runtime runs them.
class _EventTimer implements Timer {
  /// Those that wait for no time, in the order in which they were made.
  static final List<_EventTimer> _immediate = [];

  /// Those that wait, the first ones first.
  static final List<_EventTimer> _waiting = [];
  static int _count = 0;

  void Function(Timer timer)? _callback;
  final int _milliseconds;
  final bool _repeats;
  int _wakeup;
  int _id;
  int _tick = 0;

  _EventTimer(int milliseconds, this._callback, this._repeats)
    : _milliseconds = milliseconds < 0 ? 0 : milliseconds,
      _id = _count++,
      _wakeup = milliseconds <= 0 ? _now : _now + 1 + milliseconds {
    _enqueue();
  }

  static int get _now => steadyTime() ~/ 1000000;

  bool _isBefore(_EventTimer other) =>
      _wakeup < other._wakeup || _wakeup == other._wakeup && _id < other._id;

  void _enqueue() {
    if (_milliseconds == 0) {
      _immediate.add(this);
      return;
    }
    var at = _waiting.length;
    while (at > 0 && _isBefore(_waiting[at - 1])) {
      at--;
    }
    _waiting.insert(at, this);
  }

  bool get isActive => _callback != null;

  int get tick => _tick;

  void cancel() {
    _callback = null;
    _waiting.remove(this);
  }

  /// Runs the timers that come next, or waits for the first one. Returns
  /// whether there were any.
  static bool _runNext({bool waits = true}) {
    final pending = <_EventTimer>[];
    if (_immediate.isNotEmpty) {
      final first = _immediate.removeAt(0);
      while (_waiting.isNotEmpty && _waiting.first._isBefore(first)) {
        pending.add(_waiting.removeAt(0));
      }
      pending.add(first);
    } else {
      if (_waiting.isEmpty) return false;
      final rest = _waiting.first._wakeup - _now;
      if (rest > 0) {
        // What happens outside comes first.
        if (waits) _wait(rest > 1000 ? 1000000 : rest * 1000);
        return true;
      }
      final now = _now;
      while (_waiting.isNotEmpty && _waiting.first._wakeup <= now) {
        pending.add(_waiting.removeAt(0));
      }
    }
    for (var i = 0; i < pending.length; i++) {
      pending[i]._run();
    }
    return true;
  }

  void _run() {
    final callback = _callback;
    // Timers that ran before can cancel this one.
    if (callback == null) return;
    if (!_repeats) {
      _callback = null;
    } else if (_milliseconds > 0) {
      final missed = (_now - _wakeup) ~/ _milliseconds;
      if (missed > 0 && _now - _wakeup > _milliseconds) {
        _wakeup += missed * _milliseconds;
        _tick += missed;
      }
    }
    _tick++;
    callback(this);
    if (_repeats && _callback != null) {
      _id = _count++;
      _wakeup = _milliseconds > 0 ? _wakeup + _milliseconds : _now;
      _enqueue();
    }
    _runImmediate();
  }
}
