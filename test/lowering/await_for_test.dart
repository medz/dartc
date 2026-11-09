import 'dart:async';

import 'package:dartc/ir.dart';
import 'package:dartc/analyzer.dart';
import 'package:dartc/lowering.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';
import 'fixtures/await_for.dart' as sdk;
import 'fixtures/effects.dart' as effects;

void main() {
  late IrInterpreter runner;
  late Map<String, IrFunction> functions;
  setUpAll(() async {
    final program = await AnalysisSession([
      'test/lowering/fixtures/await_for.dart',
    ]).use((input) => Lowering().lower(input).program);
    runner = IrInterpreter(program, {
      (Uri.base.resolve('test/lowering/fixtures/effects.dart'), 'tick'):
          effects.tick,
    });
    functions = {for (final f in program.functions) f.target.name: f};
  });

  Stream<int> source({bool fail = false}) async* {
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

  test(
    'stream loops preserve continue and await cleanup on every exit',
    () async {
      for (var mode = 0; mode < 5; mode++) {
        for (final fail in [false, true]) {
          effects.calls.clear();
          final expected = await sdk.sum(source(fail: fail), mode);
          final calls = List.of(effects.calls);
          effects.calls.clear();
          final actual = await runner.resolveAsync(
            runner.run(functions['sum']!, [source(fail: fail), mode]),
          );
          expect(actual, expected, reason: 'mode $mode / error $fail');
          expect(effects.calls, calls, reason: 'mode $mode / error $fail');
        }
      }
    },
  );

  test(
    'collection stream loops use the same iteration and cleanup protocol',
    () async {
      effects.calls.clear();
      final expected = await sdk.collected(source());
      final calls = List.of(effects.calls);
      effects.calls.clear();
      expect(
        await runner.resolveAsync(
          runner.run(functions['collected']!, [source()]),
        ),
        expected,
      );
      expect(effects.calls, calls);
    },
  );

  test(
    'canceling an async generator also cancels its active stream loop',
    () async {
      for (final native in [true, false]) {
        effects.calls.clear();
        final stream = native
            ? sdk.forwarded(source())
            : runner.run(functions['forwarded']!, [source()])
                  as Stream<Object?>;
        final iterator = StreamIterator(stream);
        expect(await iterator.moveNext(), isTrue);
        expect(iterator.current, 1);
        await iterator.cancel();
        expect(effects.calls, [50, 70]);
      }
    },
  );
}
