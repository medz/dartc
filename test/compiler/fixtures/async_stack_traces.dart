import 'dart:async';

import 'futures.dart' show churn;

Future<StackTrace> stackLeaf() async {
  await Future<void>.value();
  churn();
  return StackTrace.current;
}

Future<StackTrace> stackMiddle() async => await stackLeaf();
Future<StackTrace> stackOuter() async => await stackMiddle();

StackTrace thenCallback(int value) => StackTrace.current;
Future<StackTrace> thenParent() async =>
    await Future<int>.value(1).then(thenCallback);

Future<StackTrace> waitParent() async =>
    (await Future.wait([stackLeaf()])).single;
Future<StackTrace> timeoutParent() async =>
    await stackLeaf().timeout(const Duration(days: 1));

Stream<StackTrace> stackStream() async* {
  await Future<void>.value();
  yield StackTrace.current;
}

Stream<StackTrace> delegatedStream() async* {
  yield* stackStream();
}

Future<StackTrace> streamParent() async {
  await for (final trace in delegatedStream()) {
    return trace;
  }
  throw StateError('Stream did not yield');
}

Future<StackTrace> boxedLink() {
  final done = Completer<StackTrace>();
  @pragma('vm:awaiter-link')
  Object link = Object();
  void callback() {
    if (link is! Future<StackTrace>) throw StateError('Lost captured future');
    final trace = StackTrace.current;
    done.complete(trace);
  }

  link = done.future;
  scheduleMicrotask(callback);
  return done.future;
}

Future<StackTrace> boxedParent() async => await boxedLink();

Future<Never> errorLeaf() async {
  await Future<void>.value();
  throw StateError('async failure');
}

Future<void> rethrowParent() async {
  try {
    await errorLeaf();
  } catch (_) {
    churn();
    rethrow;
  }
}

void checkUnreadLinks() {
  var initialized = false;
  @pragma('vm:awaiter-link')
  late Object lazy = () {
    initialized = true;
    return Object();
  }();
  StackTrace unread() {
    final trace = StackTrace.current;
    if (initialized) print(lazy);
    return trace;
  }

  final trace = unread();
  @pragma('vm:awaiter-link')
  late StackTrace Function() cycle;
  cycle = () {
    final trace = StackTrace.current;
    if (initialized) cycle();
    return trace;
  };
  final cyclic = cycle();
  if (initialized || trace.toString().isEmpty || cyclic.toString().isEmpty) {
    throw StateError('Stack capture evaluated an awaiter link');
  }
  print('unread-links:ok');
}

Future<StackTrace> wrappedZone() async => await runZoned(
  stackOuter,
  zoneSpecification: ZoneSpecification(
    registerUnaryCallback: <R, T>(self, parent, zone, callback) {
      @pragma('vm:awaiter-link')
      final next = callback;
      return parent.registerUnaryCallback<R, T>(zone, (value) => next(value));
    },
  ),
);

Future<StackTrace> completedAwait() async {
  await Future<void>.value();
  return StackTrace.current;
}

Future<void> emitDetached() async {
  final trace = await completedAwait();
  emit('completed', trace);
}

void emit(String label, StackTrace trace) {
  churn();
  print('BEGIN $label');
  print(trace);
  print('END $label');
}

Future<void> main() async {
  emit('nested', await stackOuter());
  emit('then', await thenParent());
  emit('wait', await waitParent());
  emit('timeout', await timeoutParent());
  emit('stream', await streamParent());
  emit('boxed', await boxedParent());
  emit('zone', await runZoned(stackOuter, zoneValues: {'stack': true}));
  emit('wrapped-zone', await wrappedZone());
  await emitDetached();
  try {
    await rethrowParent();
  } catch (error, trace) {
    if ((error as Error).stackTrace.toString() != trace.toString()) {
      throw StateError('Rethrow changed the original trace');
    }
    emit('rethrow', trace);
  }
  checkUnreadLinks();
}
