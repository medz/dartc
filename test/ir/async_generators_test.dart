import 'dart:async';

import 'package:dartc/ir.dart';
import 'package:test/test.dart';

import '../lowering/fixture_runner.dart';

final _stream = CoreTypes.streamOf(.integer);
final _library = Uri.parse('memory:async_generator');
final _mark = FunctionTarget(_library, 'mark', .integer, [.integer]);

// The same observable body is built below as IR, including its finally path.
Stream<int> _sdk(Stream<int> source, FutureOr<int> Function(int) mark) async* {
  try {
    final value = await mark(1);
    mark(6);
    yield value;
    try {
      yield* source;
    } catch (_) {
      mark(3);
    }
    mark(2);
  } finally {
    await mark(4);
    mark(5);
  }
}

final _function = _graph();

IrFunction _graph() {
  final target = FunctionTarget(_library, 'events', _stream, [_stream]);
  final entry = Block([_stream]),
      publish = Block([.integer]),
      delegate = Block(),
      caught = Block([.object, .stackTrace]),
      resumed = Block(),
      cleanup = Block(),
      done = Block();
  Value mark(Block b, int n) =>
      b.emit(DirectCall(_mark, [Constant.integer(n)]));
  final first = AwaitResult(.integer);
  entry.finish(Await(mark(entry, 1), first, onResume: Jump(publish, [first])));
  mark(publish, 6);
  publish.finish(
    Yield(publish.parameters.single, Jump(delegate), onCancel: Jump(cleanup)),
  );
  delegate.finish(
    YieldStream(
      entry.parameters.single,
      Jump(resumed),
      onCancel: Jump(cleanup),
      onThrow: Jump(caught, [UnwindValue.exception, UnwindValue.stackTrace]),
    ),
  );
  mark(caught, 3);
  caught.finish(Jump(resumed));
  mark(resumed, 2);
  resumed.finish(Jump(cleanup));
  cleanup.finish(
    Await(mark(cleanup, 4), AwaitResult(.integer), onResume: Jump(done)),
  );
  mark(done, 5);
  done.finish(const Return());
  return IrFunction(
    target,
    [entry, publish, delegate, caught, resumed, cleanup, done],
    bodyKind: .asyncGenerator,
    yieldType: .integer,
  );
}

Stream<Object?> _ir(Stream<int> source, int Function(int) mark) =>
    FixtureRunner(IrProgram([], [_function]), {
      (_library, 'mark'): mark,
    }).run(_function, [source]) as Stream<Object?>;

void main() {
  test(
    'the stream, resume, cancel and delegation-error edges are inspectable',
    () {
      expect(CoreTypes.stream.library, Uri.parse('dart:async'));
      final text = StringBuffer();
      _function.writeTo(text);
      expect('$text', contains('Stream<int> async*<int>'));
      expect('$text', contains('cancel b5() unwind b3(exception, stackTrace)'));
      expect(_function.blocks[2].successors.map((edge) => edge.target), [
        _function.blocks[4],
        _function.blocks[5],
        _function.blocks[3],
      ]);
      expect(_function.callees, {_mark});
    },
  );

  test(
    'invalid yields cannot enter a handler or use the wrong producer type',
    () {
      final end = Block()..finish(const Return());
      void rejects(Terminator op, {bool sync = false}) {
        final entry = Block()..finish(op);
        final target = FunctionTarget(
          _library,
          'bad',
          sync ? CoreTypes.iterableOf(.integer) : _stream,
          [],
        );
        expect(
          () => IrFunction(
            target,
            [entry, end],
            bodyKind: sync ? .syncGenerator : .asyncGenerator,
            yieldType: .integer,
          ),
          throwsStateError,
        );
      }

      rejects(Yield(const Constant.integer(1), Jump(end)));
      rejects(
        Yield(const Constant.string('bad'), Jump(end), onCancel: Jump(end)),
      );
      rejects(
        Yield(const Constant.integer(1), Jump(end), onCancel: Jump(end)),
        sync: true,
      );
      rejects(
        YieldStream(const Constant.integer(1), Jump(end), onCancel: Jump(end)),
      );
      final handler = Block([.object])..finish(const Return());
      final entry = Block()
        ..finish(
          Yield(
            const Constant.integer(1),
            Jump(end),
            onCancel: Jump(handler, [UnwindValue.exception]),
          ),
        );
      expect(
        () => IrFunction(
          FunctionTarget(_library, 'bad', _stream, []),
          [entry, end, handler],
          bodyKind: .asyncGenerator,
          yieldType: .integer,
        ),
        throwsStateError,
      );
    },
  );

  for (final stopAt in [null, 1, 7]) {
    test(
      'SDK event order, pause, delegation and cleanup with stopAt=$stopAt',
      () async {
        Future<List<Object>> observe(
          Stream<Object?> Function(Stream<int>, int Function(int)) make,
        ) async {
          final events = <Object>[];
          final source = StreamController<int>(
            onCancel: () => events.add('source closed'),
          );
          source
            ..add(7)
            ..addError('source error')
            ..add(8);
          unawaited(source.close());
          final output = make(source.stream, (n) {
            events.add('mark$n');
            return n;
          });
          expect(events, isEmpty);
          final first = Completer<void>(), stopped = Completer<void>();
          late final StreamSubscription<Object?> subscription;
          subscription = output.listen(
            (value) {
              events.add(value!);
              if (value == 1) {
                subscription.pause();
                first.complete();
              }
              if (value == stopAt) {
                subscription.cancel().then((_) => stopped.complete());
              }
            },
            onError: (Object e) => events.add(e),
            onDone: stopped.complete,
          );
          await first.future;
          await Future<void>.delayed(Duration.zero);
          if (stopAt != 1) expect(events, ['mark1', 'mark6', 1]);
          subscription.resume();
          await stopped.future;
          return events;
        }

        final expected = await observe(_sdk);
        expect(await observe(_ir), expected);
        expect(expected.sublist(expected.length - 2), ['mark4', 'mark5']);
        if (stopAt == null) {
          expect(expected, containsAllInOrder([7, 'source error', 8, 'mark2']));
          expect(expected, isNot(contains('mark3')));
        }
      },
    );
  }

  test('cancel during await resumes the body until the next yield', () async {
    for (final make
        in <Stream<Object?> Function(Stream<int>, int Function(int))>[
          _sdk,
          _ir,
        ]) {
      final events = <Object>[], done = Completer<void>();
      late final StreamSubscription<Object?> subscription;
      subscription = make(Stream<int>.empty(), (n) {
        events.add(n);
        if (n == 1) {
          scheduleMicrotask(() {
            events.add('cancel');
            subscription.cancel().then((_) => done.complete());
          });
        }
        return n;
      }).listen((_) => events.add('event'));
      await done.future;
      expect(events, [1, 'cancel', 6, 4, 5]);
    }
  });

  test(
    'a failed listen enters the local handler; failed cleanup reaches cancel',
    () async {
      for (final make
          in <Stream<Object?> Function(Stream<int>, int Function(int))>[
            _sdk,
            _ir,
          ]) {
        final source = StreamController<int>()..close();
        await source.stream.drain<void>();
        final calls = <int>[];
        expect(
          await make(source.stream, (n) {
            calls.add(n);
            return n;
          }).toList(),
          [1],
        );
        expect(calls, [1, 6, 3, 2, 4, 5]);
        final iterator = StreamIterator(
          make(Stream<int>.empty(), (n) {
            if (n == 4) throw StateError('cleanup');
            return n;
          }),
        );
        expect(await iterator.moveNext(), isTrue);
        await expectLater(iterator.cancel(), throwsStateError);
      }
    },
  );
}
