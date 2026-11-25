// long
import 'dart:async';
import 'dart:developer';

Future<void> main() async {
  Timeline.startSync('a', arguments: {'k': 1}, flow: Flow.begin());
  Timeline.instantSync('i', arguments: {'k': 1});
  Timeline.finishSync();
  print(Timeline.timeSync('t', () => 5, arguments: {'k': 2})); // expect: 5
  try {
    Timeline.timeSync('t', () => throw 'x');
  } catch (e) {
    print(e);
  }
  // expect: x
  try {
    Timeline.finishSync();
  } catch (e) {
    print(e);
  }
  // expect: Bad state: Uneven calls to startSync and finishSync
  final a = TimelineTask(), b = TimelineTask(parent: a, filterKey: 'f');
  a.start('s', arguments: {'q': 2});
  b.start('r');
  b.instant('n');
  b.finish(arguments: {'z': 3});
  a.finish();
  try {
    a.finish();
  } catch (e) {
    print(e);
  }
  // expect: Bad state: Uneven calls to start and finish
  // Where they start differs from run to run.
  final first = a.pass();
  print((
    b.pass() - first,
    TimelineTask.withTaskId(9).pass(),
    Flow.begin().id - first,
  )); // expect: (1, 9, 2)
  print((
    Flow.begin(id: 4).id,
    Flow.step(7).id,
    Flow.end(8).id,
  )); // expect: (4, 7, 8)
  final before = Timeline.now;
  await Future.delayed(const Duration(milliseconds: 20));
  final took = Timeline.now - before;
  print((took >= 15000, took < 5000000)); // expect: (true, true)
  log(
    'hello',
    name: 'n',
    level: 5,
    error: 'e',
    stackTrace: StackTrace.empty,
    sequenceNumber: 3,
    time: DateTime(2020),
    zone: Zone.current,
  );
  log('again');
  print(const bool.fromEnvironment('dart.library.developer')); // expect: true
}
