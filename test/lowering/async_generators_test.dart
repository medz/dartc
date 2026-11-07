import 'dart:async';

import 'package:dartc/ir.dart';
import 'package:dartc/lowering.dart';
import 'package:test/test.dart';

import 'fixture_runner.dart';
import 'fixtures/async_generators.dart' as sdk;
import 'fixtures/effects.dart' as effects;

void main() {
  late IrProgram program;
  late FixtureRunner runner;
  late Map<String, IrFunction> functions;
  setUpAll(() async {
    program = await CheckedLibraries.read([
      'test/lowering/fixtures/async_generators.dart',
    ], Lowering.lower);
    runner = FixtureRunner(program, {
      (Uri.base.resolve('test/lowering/fixtures/effects.dart'), 'tick'):
          effects.tick,
    });
    functions = {
      for (final f in program.functions)
        if (f.target.enclosing == null) f.target.name: f,
    };
  });

  Future<(List<Object?>, List<int>)> observe(
    Stream<Object?> stream, {
    int? cancelAfter,
  }) async {
    final values = <Object?>[];
    final done = Completer<void>();
    late StreamSubscription<Object?> subscription;
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
    return (values, List.of(effects.calls));
  }

  test('async generators preserve cold start, pauses, cancellation and nested finalizers', () async {
    for (final cancelAfter in [null, 1, 2]) {
      for (final name in ['events', 'finalizerYield']) {
        effects.calls.clear();
        final expected = await observe(
          name == 'events' ? sdk.events(3) : sdk.finalizerYield(),
          cancelAfter: cancelAfter,
        );
        effects.calls.clear();
        final stream = runner.run(
          functions[name]!,
          name == 'events' ? [3] : [],
        ) as Stream<Object?>;
        expect(effects.calls, isEmpty);
        final actual = await observe(stream, cancelAfter: cancelAfter);
        expect(actual.$1, expected.$1);
        expect(actual.$2, expected.$2);
      }
    }
  });

  test('yield-star forwards errors and cancellation without entering source catches', () async {
    for (final cancelAfter in [null, 1]) {
      for (final fails in [false, true]) {
        Stream<int> source() => fails
            ? Stream<int>.error(StateError('event'))
            : Stream<int>.fromIterable([1, 2]);
        effects.calls.clear();
        final expected = await observe(
          sdk.delegate(source()),
          cancelAfter: cancelAfter,
        );
        effects.calls.clear();
        final stream =
            runner.run(functions['delegate']!, [source()]) as Stream<Object?>;
        final actual = await observe(stream, cancelAfter: cancelAfter);
        expect(actual.$1, expected.$1);
        expect(actual.$2, expected.$2);
      }
    }
  });

  test('generic stream closures and FutureOr iterable returns preserve element types', () async {
    final function = functions['generic']!;
    final stream = runner.run(
      function,
      [7],
      {function.target.typeParameters.single: ValueType.integer},
    ) as Stream<Object?>;
    expect(await stream.toList(), await sdk.generic(7).toList());
    expect(
      (runner.run(functions['unionResult']!, []) as Iterable).toList(),
      (sdk.unionResult() as Iterable).toList(),
    );
    expect(function.bodyKind, FunctionBodyKind.asyncGenerator);
    expect(function.blocks.any((b) => b.end is YieldStream), isTrue);
  });
}
