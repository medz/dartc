import 'dart:async';
import 'dart:ffi';

import '../../frontend/lowering/fixtures/async_functions.dart' as cases;
import '../../frontend/lowering/fixtures/effects.dart' as effects;
import 'futures.dart' show Payload, churn;

Future<void> check(Future<Object?> Function() run) async {
  effects.calls.clear();
  final value = await run();
  print('$value | ${effects.calls.join(',')}');
}

class ForwardFuture<T>(final T value) implements Future<T> {
  @override
  Future<R> then<R>(FutureOr<R> Function(T) onValue, {Function? onError}) =>
      Future<T>.value(value).then(onValue, onError: onError);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('$invocation');
}

class InvalidFuture<T>() implements Future<T> {
  @override
  Future<R> then<R>(FutureOr<R> Function(T) onValue, {Function? onError}) {
    (onValue as dynamic)('wrong');
    throw StateError('Accepted an invalid callback value');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('$invocation');
}

Future<String> userFutures() async {
  final Future<num> valid = ForwardFuture<int>(7),
      invalid = InvalidFuture<int>();
  final value = await valid;
  try {
    await invalid;
  } on TypeError {
    return '$value:checked';
  }
  throw StateError('Missing callback type check');
}

Future<String> lifetime() async {
  final value = Payload(42, 'retained 中文🙂');
  final gate = Completer<void>();
  scheduleMicrotask(() {
    churn();
    gate.complete();
  });
  await gate.future;
  final text = value.text;
  churn();
  // ignore: await_only_futures
  await 0;
  return '${value.id}:$text';
}

Future<String> savedRepresentations(
  int integer,
  double floating,
  Pointer<Int8> pointer,
) async {
  final result = floating + await Future<double>.value(1.25);
  return '$integer:$result:${pointer.address}';
}

Future<String> zones() {
  final done = Completer<String>();
  runZonedGuarded(
    () async {
      await Future<void>.delayed(Duration.zero);
      if (Zone.current['name'] != 'async') throw 'wrong zone';
      throw StateError('resumed');
    },
    (error, trace) {
      done.complete(
        '${error is StateError}:${trace.toString().contains('async_functions.dart:78:')}',
      );
    },
    zoneValues: {'name': 'async'},
  );
  return done.future;
}

Future<void> main() async {
  for (final flag in [false, true]) {
    await check(() => cases.ordering(flag));
    await check(() => cases.pendingCompletion(flag));
    await check(() => cases.callbackProtocols(flag));
    for (final failure in [false, true]) {
      await check(() => cases.returnOrAwait(flag, failure));
    }
  }
  for (final run in <Future<Object?> Function()>[
    cases.dynamicReturnCheck,
    cases.resultTypes,
    cases.genericCases,
    cases.futureValueArm,
    cases.nestedAwait,
    cases.finalizerOverride,
    cases.returnSnapshot,
    cases.resumedRethrow,
    cases.neverAwait,
    cases.manyAwaits,
    cases.dynamicVoid,
    cases.errorCallbacks,
    cases.factories,
    cases.rejectedCompletion,
    cases.unsupportedFuture,
    cases.syncIdentity,
    cases.protocolErrors,
    cases.asynchronousErrors,
    cases.suspendedExpressions,
    cases.loopFinalizers,
    cases.asynchronousMembers,
    cases.concurrentCaptures,
    cases.voidPayloads,
    cases.completionTypes,
    cases.unsupportedEventQueue,
    cases.unsupportedTearOff,
    userFutures,
    zones,
    () => savedRepresentations(42, 3.5, Pointer.fromAddress(1234)),
    lifetime,
  ]) {
    await check(run);
  }
  print('done');
}
