import 'dart:async';

Future<String> constructors() {
  final order = <String>[];
  final sync = Future.sync(() {
    order.add('sync');
    return 1;
  });
  final microtask = Future.microtask(() {
    order.add('microtask');
    return 2;
  });
  final event = Future(() {
    order.add('event');
    return 3;
  });
  order.add('caller');
  return Future.wait([sync, microtask, event]).then((values) {
    return 'constructors: ${order.join(',')} = ${values.join(',')}';
  });
}

Future<String> completers() {
  final async = Completer<String>(), sync = Completer<String>.sync();
  final order = <String>[];
  final a = async.future.then((value) => order.add(value));
  final b = sync.future.then((value) => order.add(value));
  async.complete('async');
  sync.complete('sync');
  order.add('caller');
  try {
    async.complete('twice');
  } on StateError {
    order.add('rejected');
  }
  final adopted = Completer<double>()..complete(Future.value(3.5));
  return Future.wait([a, b]).then((_) => adopted.future).then((value) {
    return 'completers: ${order.join(',')} = $value';
  });
}

Future<String> errors() {
  final error = StateError('first');
  final stack = StackTrace.fromString('supplied');
  final done = Completer<String>();
  final result = done.future.catchError((Object caught, StackTrace trace) {
    if (!identical(error, caught) || trace.toString() != 'supplied') {
      throw StateError('Lost error or stack');
    }
    return 'recovered';
  }, test: (error) => error is StateError);
  done.completeError(error, stack);
  return result
      .then((value) {
        return Future<String>.error(
          error,
          StackTrace.fromString('second'),
        ).catchError((Object caught, StackTrace trace) {
          return '$value,${error.stackTrace},$trace';
        });
      })
      .whenComplete(() => Future.value());
}

Future<String> combinators() {
  final cleaned = <String>[];
  final fast = Completer<String>();
  final slow = Completer<String>();
  final wait = Future.wait([
    Future.value('first'),
    fast.future,
    slow.future,
  ], cleanUp: cleaned.add);
  fast.completeError(StateError('failed'));
  slow.complete('last');
  return wait
      .then<String>(
        (_) => 'unexpected',
        onError: (Object error) {
          return cleaned.join(',');
        },
      )
      .then((cleanup) {
        return Future.any([
          Future.value('winner'),
          Future.delayed(const Duration(milliseconds: 1), () => 'later'),
        ]).then((winner) => 'combinators: $cleanup;$winner');
      });
}

Future<String> timeouts() {
  final pending = Completer<String>();
  return pending.future
      .timeout(Duration.zero, onTimeout: () => 'timeout')
      .then((value) {
        pending.complete('late');
        return Future.value(value).timeout(const Duration(seconds: 1));
      })
      .then((value) {
        return Completer<String>().future
            .timeout(Duration.zero)
            .catchError(
              (Object error) => error is TimeoutException ? value : 'wrong',
            );
      });
}

Future<String> zones() {
  final result = Completer<String>();
  runZonedGuarded(
    () {
      Future.value('value').then((value) {
        if (Zone.current['name'] != 'creation') throw StateError('Wrong zone');
        throw StateError(value);
      });
    },
    (Object error, StackTrace stack) {
      result.complete(
        'zones: ${error is StateError},${stack.toString().isNotEmpty}',
      );
    },
    zoneValues: {'name': 'creation'},
  );
  return result.future;
}

final class Payload(final int id, final String text);

int churn() {
  var sum = 0;
  for (var i = 0; i < 40000; i++) {
    sum += Payload(i, 'temporary').id;
  }
  return sum;
}

Future<String> lifetimes() {
  final value = Payload(42, 'retained 中文🙂');
  final pending = Completer<Payload>();
  final result = pending.future.then((actual) {
    if (!identical(actual, value) || churn() != 799980000) {
      throw StateError('Lost future value or callback capture');
    }
    return 'lifetime: ${actual.id},${actual.text}';
  });
  scheduleMicrotask(() {
    churn();
    pending.complete(Future.value(value));
    churn();
  });
  return result;
}

Future<String> typedCallbacks() {
  dynamic invalidResult = 'invalid result';
  return Future<int>.error(StateError('typed'))
      .catchError((_) => invalidResult)
      .then<String>(
        (_) => 'unexpected',
        onError: (Object error) => 'typed callback: ${error is ArgumentError}',
      );
}

void main() {
  Future.forEach([
    constructors,
    completers,
    errors,
    combinators,
    timeouts,
    zones,
    lifetimes,
    typedCallbacks,
    records,
  ], (run) => run().then(print));
}

Future<String> records() => (Future.value(42), Future.value('record')).wait
    .then((value) => '${value.$1},${value.$2}')
    .then(
      (success) => (Future.value(7), Future<String>.error('failed')).wait.then(
        (_) => 'unexpected',
        onError: (Object failure) {
          final error = failure as ParallelWaitError;
          return '$success;${error.values},${error.errors.$2.error}';
        },
      ),
    );
