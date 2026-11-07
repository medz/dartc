// Scalar awaits deliberately test asynchronous resumption.
// ignore_for_file: await_only_futures

import 'dart:async';

import 'effects.dart';

Stream<int> events(int count) async* {
  tick(1);
  try {
    for (var i = 0; i < count; i++) {
      try {
        yield await tick(10 + i);
      } finally {
        await tick(20 + i);
      }
    }
  } finally {
    await tick(30);
    tick(31);
  }
}

Stream<int> delegate(Stream<int> source) async* {
  try {
    try {
      yield* source;
    } catch (_) {
      tick(2);
    }
    tick(3);
  } finally {
    await tick(4);
    tick(5);
  }
}

Stream<T> generic<T>(T value) async* {
  Stream<T> local() async* {
    yield value;
  }

  yield* local();
}

Stream<int> finalizerYield() async* {
  try {
    yield 1;
  } finally {
    tick(2);
    yield 3;
    tick(4);
  }
}

FutureOr<Iterable<int>> unionResult() sync* {
  yield 1;
}
