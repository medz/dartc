import 'dart:async';

import 'finalization.dart';
import 'heap.dart';
import 'memory.dart';

/// Runs SDK microtasks before each finalization event at an idle Dart boundary.
final class EventLoop(final FinalizationQueue finalizers) {
  void Function()? _microtasks;
  _Timer? _timers;
  bool _running = false;

  void scheduleMicrotasks(void Function() drain) => _microtasks = drain;

  void visitRoots(ReferenceVisitor visitor) {
    visitor.visit(_microtasks);
    visitor.visit(_timers);
  }

  Timer createTimer(
    Duration duration,
    void Function(Timer) callback,
    bool periodic,
  ) {
    final delay = duration.inMicroseconds < 0 ? 0 : duration.inMicroseconds;
    final timer = _Timer(this, callback, delay, periodic);
    final now = Memory.clock() ~/ 1000;
    timer._deadline = delay > 0x7fffffffffffffff - now
        ? 0x7fffffffffffffff
        : now + delay;
    _insert(timer);
    return timer;
  }

  void _insert(_Timer timer) {
    _Timer? previous;
    var next = _timers;
    while (next != null && next._deadline <= timer._deadline) {
      previous = next;
      next = next._next;
    }
    timer._next = next;
    if (previous == null) {
      _timers = timer;
    } else {
      previous._next = timer;
    }
  }

  void _cancel(_Timer timer) {
    _Timer? previous;
    for (var next = _timers; next != null; next = next._next) {
      if (identical(next, timer)) {
        if (previous == null) {
          _timers = next._next;
        } else {
          previous._next = next._next;
        }
        break;
      }
      previous = next;
    }
    timer._next = null;
    timer._callback = null;
  }

  void run() {
    if (_running) return;
    _running = true;
    try {
      for (;;) {
        for (var drain = _microtasks; drain != null; drain = _microtasks) {
          _microtasks = null;
          drain();
        }
        if (finalizers.deliverNext()) continue;
        final timer = _timers;
        if (timer == null) return;
        final now = Memory.clock() ~/ 1000;
        final remaining = timer._deadline - now;
        if (remaining > 0) {
          final seconds = remaining ~/ 1000000;
          Memory.sleep(
            seconds > 0x7fffffff ? 0x7fffffff : seconds,
            (remaining % 1000000) * 1000,
          );
          continue;
        }
        _timers = timer._next;
        timer._next = null;
        final callback = timer._callback!;
        timer._tick++;
        if (timer._periodic) {
          if (timer._interval > 0) {
            final missed = (now - timer._deadline) ~/ timer._interval;
            timer._tick += missed;
            timer._deadline += (missed + 1) * timer._interval;
          } else {
            timer._deadline = now;
          }
          _insert(timer);
        } else {
          timer._callback = null;
        }
        try {
          callback(timer);
        } catch (error, trace) {
          Zone.current.handleUncaughtError(error, trace);
        }
      }
    } finally {
      _running = false;
    }
  }
}

final class _Timer(
  final EventLoop _loop,
  void Function(Timer) callback,
  final int _interval,
  final bool _periodic,
) implements Timer {
  void Function(Timer)? _callback = callback;
  _Timer? _next;
  int _deadline = 0, _tick = 0;
  @override
  int get tick => _tick;
  @override
  bool get isActive => _callback != null;
  @override
  void cancel() => _loop._cancel(this);
}
