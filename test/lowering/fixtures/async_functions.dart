// Deliberately exercises valid but discouraged asynchronous control flow.
// ignore_for_file: await_only_futures, control_flow_in_finally, unawaited_return_in_try_block, null_argument_to_non_null_type, invalid_return_type_for_catch_error, argument_type_not_assignable_to_error_handler, unnecessary_type_check

import 'dart:async';

import 'effects.dart';

Future<int> scalar() async {
  tick(1);
  return 2;
}

Future<int> scalarAwait() async {
  tick(1);
  final value = await tick(2);
  tick(3);
  return value;
}

Future<String> ordering(bool suspended) async {
  final future = suspended ? scalarAwait() : scalar();
  tick(4);
  final observed = future.then((value) {
    tick(5);
    return value;
  });
  scheduleMicrotask(() => tick(6));
  final result = await observed;
  tick(7);
  await Future<void>.value();
  return '$result';
}

Future<String> pendingCompletion(bool synchronous) async {
  final completer = synchronous ? Completer<int>.sync() : Completer<int>();
  Future<int> work() async {
    tick(1);
    final result = await completer.future;
    tick(2);
    return result;
  }

  final future = work();
  tick(3);
  final same = identical(completer.future, completer.future);
  completer.complete(4);
  tick(5);
  return '${await future}:$same:${completer.isCompleted}';
}

Future<String> returnOrAwait(bool explicitAwait, bool failure) async {
  final completer = Completer<int>();
  Future<int> body() async {
    try {
      tick(1);
      if (explicitAwait) return await completer.future;
      return completer.future;
    } catch (_) {
      tick(2);
      return 9;
    } finally {
      tick(3);
    }
  }

  final result = body();
  tick(4);
  if (failure) {
    completer.completeError('failure');
  } else {
    completer.complete(7);
  }
  try {
    return '${await result}';
  } catch (error) {
    tick(5);
    return '$error';
  }
}

Future<int> returnCheck(dynamic value) async {
  try {
    return value;
  } catch (_) {
    tick(1);
    return 9;
  } finally {
    tick(2);
  }
}

Future<String> dynamicReturnCheck() async => '${await returnCheck('bad')}';

Object broad() async => 1;
FutureOr<Object> explicitFutureOr() async => 1;
FutureOr<Object>? nullableFutureOr() async => 1;
Future<String> resultTypes() async {
  final a = broad(), b = explicitFutureOr(), c = nullableFutureOr();
  final result =
      '${a is Future<Object>}:${a is Future<Object?>}:${b is Future<Object>}:${c is Future<Object>}';
  await a;
  await b;
  await c;
  return result;
}

Future<Object> retainValue(Object value) async => value;
Future<String> futureValueArm() async {
  final inner = Future<Object?>.value(null);
  final outer = retainValue(inner);
  final a = outer.then((_) => tick(1));
  scheduleMicrotask(() => tick(2));
  final b = outer.then((_) => tick(3));
  final result = await outer;
  await a;
  await b;
  await Future<void>.value();
  return '${identical(result, inner)}';
}

Future<T> generic<T>(FutureOr<T> value) async => await value;
Future<String> genericCases() async {
  final a = await generic<int>(3);
  final b = await generic<int>(Future<int>.value(4));
  final inner = Future<Object>.value(5);
  final c = await generic<Future<Object>>(inner);
  final d = await generic<int?>(null);
  final e = await generic<Null>(null);
  return '$a:$b:${identical(c, inner)}:$d:$e';
}

Future<String> nestedAwait() async {
  final inner = Future<Object>.value(1);
  final FutureOr<Future<Object>> value = inner;
  final result = await value;
  return '${identical(result, inner)}';
}

Future<int> finalizerOverride() async {
  final completer = Completer<int>();
  scheduleMicrotask(() => completer.complete(2));
  try {
    return completer.future;
  } finally {
    await tick(1);
    return 3;
  }
}

Future<String> returnSnapshot() async {
  var value = 1;
  Future<int> body() async {
    try {
      return value;
    } finally {
      await 0;
      value = 2;
      tick(value);
    }
  }

  final result = await body();
  return '$result:$value';
}

StackTrace originalTrace() {
  try {
    throw 1;
  } catch (_, trace) {
    return trace;
  }
}

Future<String> resumedRethrow() async {
  final original = originalTrace();
  try {
    await Future<int>.error('failure', original);
  } catch (error, trace) {
    await 0;
    try {
      rethrow;
    } catch (again, againTrace) {
      return '$error:$again:${identical(original, trace)}:${identical(trace, againTrace)}';
    }
  }
  return 'missing';
}

Future<int> neverAwait() async {
  try {
    await Future<Never>.error('never');
  } catch (_) {
    return 1;
  }
}

Future<int> manyAwaits() async {
  var sum = 0;
  for (var i = 0; i < 1500; i++) {
    sum += await 1;
  }
  return sum;
}

void asyncVoid() async {
  tick(1);
  await 0;
  tick(2);
}

Future<String> dynamicVoid() async {
  dynamic fn = asyncVoid;
  final value = fn();
  final type = value is Future<void>;
  await value;
  return '$type';
}

Future<String> callbackProtocols(bool dynamicReceiver) async {
  final completer = Completer<int>();
  final Future<int> source = completer.future;
  dynamic dynamicSource = source;
  final Future<int> result = dynamicReceiver
      ? dynamicSource.then<int>((int value) => Future<int>.value(value + 1))
      : source.then<int>((value) => Future<int>.value(value + 1));
  scheduleMicrotask(() => completer.complete(3));
  try {
    return '${await result}';
  } finally {
    tick(1);
    await 0;
    tick(2);
  }
}

Future<String> errorCallbacks() async {
  final first = Future<int>.error('first')
      .catchError((Object error, StackTrace trace) {
        tick(1);
        return Future<int>.value(2);
      }, test: (Object error) => error == 'first');
  final second = Future<int>.error('second').then<int>(
    (value) => value,
    onError: (Object error) {
      tick(3);
      return 4;
    },
  );
  return '${await first}:${await second}';
}

Future<String> factories() async {
  final a = Future<int>.sync(() {
    tick(1);
    return 2;
  });
  final b = Future<int>.microtask(() {
    tick(3);
    return 4;
  });
  tick(5);
  return '${await a}:${await b}';
}

Future<String> rejectedCompletion() async {
  final completer = Completer<int>();
  try {
    completer.complete();
  } catch (_) {
    tick(1);
  }
  completer.complete(2);
  return '${await completer.future}';
}

class FakeFuture<T>() implements Future<T> {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw 'fake';
}

Future<int> unsupportedFuture() async {
  try {
    return await FakeFuture<int>();
  } catch (_) {
    return 9;
  }
}

Future<String> syncIdentity() async {
  final inner = Future<int>.value(2);
  final outer = Future<num>.sync(() => inner);
  final same = identical(inner, outer);
  final narrow = outer is Future<int>;
  final fake = FakeFuture<int>();
  final fakeResult = Future<int>.sync(() => fake);
  return '$same:$narrow:${await outer}:${identical(fake, fakeResult)}';
}

Future<int> unsupportedCompletion() async =>
    Future<int>.value(1).whenComplete(() {});

Future<int> unsupportedCatch() async =>
    unsupportedFuture().catchError((Object _) => 9, test: (Object _) => true);

Future<int> unsupportedThen() async =>
    unsupportedFuture().then((x) => x, onError: (Object _) => 9);

String errorKind(Object error) => switch (error) {
  TypeError() => 'type',
  ArgumentError() => 'argument',
  StateError() => 'state',
  _ => 'other',
};

Future<String> protocolErrors() async {
  final errors = <String>[];
  void record(void Function() action) {
    try {
      action();
      errors.add('none');
    } catch (error) {
      errors.add(errorKind(error));
    }
  }

  final completer = Completer<int>()..complete(1);
  dynamic dynamicCompleter = completer;
  dynamic future = completer.future;
  record(() => Future<int>.value());
  record(() => completer.complete());
  record(() => dynamicCompleter.complete('bad'));
  record(() => future.then<int>((String value) => 1));
  record(
    () => future.then<int>((int value) => value, onError: (String e) => 0),
  );
  record(() => future.catchError((String e) => 0));
  for (final throwing in [false, true]) {
    try {
      await Future<int>.error('bad').catchError((Object _) {
        if (throwing) throw TypeError();
        return 'bad';
      });
    } catch (error) {
      errors.add(errorKind(error));
    }
  }
  final result = await Future<int>.error('bad')
      .then<int>((x) => x, onError: (Object error, [String? unused]) => 4);
  return '$errors:$result';
}

Future<int> entryChecked(int value) async {
  tick(1);
  if (value == 1) throw 'body';
  return value;
}

Future<String> asynchronousErrors() async {
  dynamic fn = entryChecked;
  try {
    fn('wrong');
  } catch (_) {
    tick(2);
  }
  final future = entryChecked(1);
  tick(3);
  try {
    return '${await future}';
  } catch (error) {
    tick(4);
    return '$error';
  }
}

int combine(int a, int b, int c) => a * 100 + b * 10 + c;
Future<String> suspendedExpressions() async {
  final result = combine(tick(1), await tick(2), tick(3));
  final values = <int>[
    tick(4),
    await tick(5),
    for (final x in [6, 7]) await tick(x),
  ];
  return '$result:$values';
}

Future<String> loopFinalizers() async {
  var result = 0;
  for (var i = 0; i < 4; i++) {
    try {
      if (i == 0) continue;
      if (i == 2) break;
      result += await tick(1);
    } finally {
      await tick(2);
      result += 10;
    }
  }
  return '$result';
}

class AsyncBox<T>(final T value) {
  Future<T> get read async => await value;
  Future<R> map<R>(R Function(T) action) async => action(await read);
  Future<T> operator +(AsyncBox<T> other) async => await other.read;
}

class AsyncIntBox(super.value) extends AsyncBox<int> {
  @override
  Future<int> get read async => (await super.read) + 1;
}

Future<String> asynchronousMembers() async {
  final box = AsyncIntBox(2);
  final closure = box.map<String>;
  return '${await closure((value) => '$value')}:${await (box + AsyncBox(4))}';
}

Future<String> concurrentCaptures() async {
  var shared = 0;
  final gate = Completer<void>();
  Future<int> work(int increment) async {
    var local = increment;
    await gate.future;
    shared += local;
    local++;
    await 0;
    return shared * 10 + local;
  }

  final first = work(1), second = work(2);
  gate.complete();
  return '${await first}:${await second}:$shared';
}

void arrowVoid() async => tick(3);
Future<void> futureVoid() async => tick(4);
Future<String> voidPayloads() async {
  dynamic first = arrowVoid, second = futureVoid;
  return '${await first()}:${await second()}';
}

Object? nullableBroad() async => null;
dynamic dynamicResult() async => 1;
Future<int>? nullableFuture() async => 2;
Future<Null> nullResult() async => null;
Future<String> completionTypes() async {
  final a = nullableBroad(),
      b = dynamicResult(),
      c = nullableFuture(),
      d = nullResult();
  final result =
      '${a is Future<Object?>}:${a is Future<Object>}:${b is Future<dynamic>}:${b is Future<int>}:${c is Future<int>}:${d is Future<Null>}';
  await a;
  await b;
  await c;
  await d;
  return result;
}

Future<int> unsupportedEventQueue() async {
  try {
    await Future<void>(() {});
    return 1;
  } catch (_) {
    return 2;
  }
}

Future<int> unsupportedTearOff() async {
  final future = Future<int>.value(1);
  try {
    final then = future.then<int>;
    return await then((x) => x);
  } catch (_) {
    return 2;
  }
}
