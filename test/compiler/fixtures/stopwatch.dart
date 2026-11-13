void check(bool value, String label) {
  if (!value) throw StateError(label);
}

void units(Stopwatch watch) {
  check(!watch.isRunning, 'conversion snapshot is stopped');
  final ticks = watch.elapsedTicks;
  check(
    watch.elapsedMicroseconds ==
        ticks * Duration.microsecondsPerSecond ~/ watch.frequency,
    'microseconds follow frequency',
  );
  check(
    watch.elapsedMilliseconds ==
        ticks * Duration.millisecondsPerSecond ~/ watch.frequency,
    'milliseconds follow frequency',
  );
  check(
    watch.elapsed == Duration(microseconds: watch.elapsedMicroseconds),
    'duration follows microseconds',
  );
}

Future<void> main() async {
  final create = Stopwatch.new;
  final watch = create();
  final start = watch.start, stop = watch.stop, reset = watch.reset;
  check(!watch.isRunning && watch.elapsedTicks == 0, 'initial state');
  check(watch.frequency > 0, 'positive frequency');
  stop();
  units(watch);

  final monitor = Stopwatch()..start();
  check(watch.frequency == monitor.frequency, 'shared frequency');
  start();
  await Future<void>.delayed(const Duration(milliseconds: 20));
  check(watch.elapsedMicroseconds >= 10000, 'clock scale');
  final running = watch.elapsedTicks;
  start();
  check(watch.elapsedTicks >= running, 'repeated start preserves elapsed');
  stop();
  final paused = watch.elapsedTicks;
  final pauseBegin = monitor.elapsedTicks;
  await Future<void>.delayed(const Duration(milliseconds: 20));
  final pauseLength = monitor.elapsedTicks - pauseBegin;
  stop();
  check(watch.elapsedTicks == paused, 'stopped state and repeated stop');
  units(watch);

  start();
  await Future<void>.delayed(const Duration(milliseconds: 20));
  stop();
  monitor.stop();
  check(watch.elapsedTicks > paused, 'restart accumulates elapsed');
  check(
    monitor.elapsedTicks - watch.elapsedTicks >= pauseLength,
    'restart excludes stopped interval',
  );
  units(watch);

  reset();
  check(!watch.isRunning && watch.elapsedTicks == 0, 'stopped reset');
  units(watch);
  monitor
    ..reset()
    ..start();
  start();
  await Future<void>.delayed(const Duration(milliseconds: 20));
  final beforeReset = monitor.elapsedTicks;
  reset();
  check(watch.isRunning, 'running reset preserves state');
  await Future<void>.delayed(const Duration(milliseconds: 20));
  stop();
  monitor.stop();
  check(watch.elapsedTicks > 0, 'running reset keeps measuring');
  check(
    watch.elapsedTicks <= monitor.elapsedTicks - beforeReset,
    'running reset clears previous elapsed',
  );
  units(watch);

  final snapshot = watch.elapsedTicks;
  var sum = 0;
  for (var i = 0; i < 4000; i++) {
    sum += List<int>.filled(64, i).last;
  }
  check(sum == 7998000, 'allocation pressure');
  check(watch.elapsedTicks == snapshot, 'stopped state survives collection');
  start();
  await Future<void>.delayed(const Duration(milliseconds: 1));
  stop();
  check(watch.elapsedTicks > snapshot, 'method values survive collection');
  units(watch);

  final dynamic other = create();
  other.start();
  other.stop();
  check(other.isRunning == false, 'dynamic methods');
  other.reset();
  check(other.elapsedTicks == 0, 'independent instance');
  check(watch.elapsedTicks > 0, 'other reset preserves original');
  print('stopwatch:ok');
}
