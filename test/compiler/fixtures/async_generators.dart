import 'dart:async';
import 'dart:ffi';

import '../../frontend/lowering/fixtures/async_generators.dart' as cases;
import '../../frontend/lowering/fixtures/await_for.dart' as loops;
import '../../frontend/lowering/fixtures/effects.dart' as effects;
import 'futures.dart' show Payload, churn;

Future<void> observe(Stream<int> stream, int? cancelAfter) async {
  final values = <Object?>[];
  final done = Completer<void>();
  late StreamSubscription<int> subscription;
  subscription = stream.listen(
    (value) async {
      values.add(value);
      subscription.pause();
      await Future<void>.delayed(Duration.zero);
      if (values.length == cancelAfter) {
        await subscription.cancel();
        done.complete();
      } else {
        subscription.resume();
      }
    },
    onError: (Object error) => values.add('$error'),
    onDone: done.complete,
  );
  await done.future;
  print('$values | ${effects.calls.join(',')}');
}

Stream<int> source(bool fail) async* {
  try {
    yield 1;
    yield 2;
    if (fail) throw StateError('source');
    yield 3;
  } finally {
    await Future<void>.value();
    effects.tick(50);
  }
}

class Producer<T>(final T value) {
  Stream<T> get values async* {
    yield value;
    await Future<void>.value();
    yield value;
  }

  Stream<U> mapped<U>(U Function(T) map) async* {
    await for (final item in values) {
      yield map(item);
    }
  }
}

Future<void> cancelWhileWaiting() async {
  final gate = Completer<void>(), started = Completer<void>();
  Stream<int> values() async* {
    try {
      effects.tick(1);
      started.complete();
      await gate.future;
      effects.tick(2);
      yield 3;
      effects.tick(4);
    } finally {
      await Future<void>.value();
      effects.tick(5);
    }
  }

  final subscription = values().listen((value) => effects.tick(value + 10));
  await started.future;
  var cancelled = false;
  final completion = subscription.cancel().then((_) => cancelled = true);
  await Future<void>.value();
  print('pending:$cancelled');
  gate.complete();
  await completion;
  print('cancelled:$cancelled:${effects.calls}');
}

Future<void> cleanupFailure() async {
  Stream<int> values() async* {
    try {
      yield 1;
    } finally {
      await Future<void>.value();
      throw StateError('cleanup');
    }
  }

  final iterator = StreamIterator(values());
  print('first:${await iterator.moveNext()}:${iterator.current}');
  try {
    await iterator.cancel();
  } on StateError catch (error) {
    print(error);
  }
}

Future<void> retained() async {
  Stream<String> values(int id, double number, Pointer<Int8> pointer) async* {
    final value = Payload(id, 'retained 中文🙂');
    yield 'ready';
    await Future<void>.value();
    yield '${value.id}:${value.text}:$number:${pointer.address}';
  }

  final iterator = StreamIterator(values(42, 3.25, Pointer.fromAddress(1234)));
  await iterator.moveNext();
  churn();
  await iterator.moveNext();
  churn();
  print(iterator.current);
  await iterator.cancel();
}

Future<void> broadcasts(bool sync) async {
  final controller = StreamController<int>.broadcast(sync: sync);
  final first = <int>[], second = <int>[];
  final firstReady = Completer<void>(), secondReady = Completer<void>();
  late StreamSubscription<int> a;
  a = controller.stream.listen((value) {
    first.add(value);
    if (value == 1) a.pause();
    if (value == 2) firstReady.complete();
  });
  final b = controller.stream.listen((value) {
    second.add(value);
    if (value == 2) secondReady.complete();
  });
  controller.add(1);
  controller.add(2);
  await secondReady.future;
  print('paused:$first:$second');
  a.resume();
  await firstReady.future;
  await b.cancel();
  controller.add(3);
  await controller.close();
  print('broadcast:$first:$second');
}

Future<void> transformations() async {
  final stream = Stream<int>.fromIterable([1, 2, 3]).asBroadcastStream();
  final first = stream.take(2).toList(), second = stream.toList();
  print('shared:${await first}:${await second}');
  print(
    await Stream<int>.fromIterable([1, 2, 3])
        .asyncMap((value) => Future.value(value + 1))
        .asyncExpand((value) => Stream<int>.fromIterable([value, value * 10]))
        .where((value) => value > 3)
        .toList(),
  );
  final recovered = Stream<int>.error(StateError('event')).transform(
    StreamTransformer<int, int>.fromHandlers(
      handleError: (error, trace, sink) => sink.add(9),
    ),
  );
  print(await recovered.toList());
}

Future<void> listeningZone() async {
  Stream<String> values() async* {
    yield '${Zone.current['name']}';
    await Future<void>.value();
    yield '${Zone.current['name']}';
  }

  final stream = values();
  final result = await runZoned(
    () => stream.toList(),
    zoneValues: {'name': 'listener'},
  );
  print('zone:$result');
}

Future<void> main() async {
  for (final cancelAfter in <int?>[null, 1, 2]) {
    for (final create in [() => cases.events(3), cases.finalizerYield]) {
      effects.calls.clear();
      final stream = create();
      print('cold:${effects.calls.isEmpty}');
      await observe(stream, cancelAfter);
    }
  }
  for (final cancelAfter in <int?>[null, 1]) {
    for (final fail in [false, true]) {
      effects.calls.clear();
      await observe(cases.delegate(source(fail)), cancelAfter);
    }
  }
  final used = Stream<int>.value(1);
  await used.drain<void>();
  effects.calls.clear();
  await observe(cases.delegate(used), null);
  for (var mode = 0; mode < 5; mode++) {
    for (final fail in [false, true]) {
      effects.calls.clear();
      final value = await loops.sum(source(fail), mode);
      print('loop:$value:${effects.calls}');
    }
  }
  effects.calls.clear();
  print('collection:${await loops.collected(source(false))}:${effects.calls}');
  effects.calls.clear();
  await observe(loops.forwarded(source(false)), 1);
  print('generic:${await cases.generic(7).toList()}');
  print('double:${await cases.generic<double>(3.25).toList()}');
  print('nullable:${await cases.generic<int?>(null).toList()}');
  print('union:${(cases.unionResult() as Iterable<int>).toList()}');
  final values = Producer<int>(5);
  final map = values.mapped;
  print('method:${await map<int>((value) => value + 2).toList()}');
  effects.calls.clear();
  final subscription = cases.events(2).listen((value) => effects.tick(value));
  await subscription.cancel();
  print('initial-cancel:${effects.calls}');
  effects.calls.clear();
  await cancelWhileWaiting();
  await cleanupFailure();
  await retained();
  await broadcasts(false);
  await broadcasts(true);
  await transformations();
  await listeningZone();
  print('done');
}
