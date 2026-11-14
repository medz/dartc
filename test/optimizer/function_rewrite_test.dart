import 'package:dartc/ir.dart';
import 'package:dartc/src/optimizer/function_rewrite.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

final _uri = Uri.parse('memory:rewrite');
final _tick = FunctionTarget(_uri, 'tick', .integer, [.integer]);

void main() {
  test(
    'discarding a proven pure invocation also removes its unused input phi',
    () {
      final helper = FunctionTarget(_uri, 'seven', .integer, [.integer]);
      final callee = IrFunction(helper, [
        Block(helper.parameterTypes)..finish(const Return(Constant.integer(7))),
      ]);
      final target = FunctionTarget(_uri, 'invoke', .integer, [.integer]);
      final entry = Block(target.parameterTypes),
          forwarded = Block([ValueType.integer]),
          normal = Block([ValueType.integer]),
          caught = Block();
      entry.finish(Jump(forwarded, entry.parameters));
      final call = DirectCall(helper, forwarded.parameters);
      forwarded.finish(
        Invoke(call, onReturn: Jump(normal, [call]), onThrow: Jump(caught)),
      );
      normal.finish(Return(normal.parameters.single));
      caught.finish(const Return(Constant.integer(-1)));
      final before = IrFunction(target, [entry, forwarded, normal, caught]);
      final after = FunctionRewrite(
        before,
        replacements: {call: const Constant.integer(7)},
        discardable: {call},
      ).run();
      expect(after.callees, isEmpty);
      for (final function in [before, after]) {
        final interpreter = IrInterpreter(
          IrProgram([], [function, callee]),
          {},
        );
        for (final input in [-2, 42]) {
          expect(interpreter.run(function, [input]), 7);
        }
      }
    },
  );

  test('a disproved branch removes its call without requiring inlining', () {
    final target = FunctionTarget(_uri, 'branch', .integer, []);
    final entry = Block(), dead = Block(), live = Block();
    final test = entry.emit(
      Equals(const Constant.integer(1), const Constant.integer(2)),
    );
    entry.finish(Branch(test, Jump(dead), Jump(live)));
    dead.finish(
      Return(dead.emit(DirectCall(_tick, [const Constant.integer(9)]))),
    );
    live.finish(const Return(Constant.integer(7)));
    final before = IrFunction(target, [entry, dead, live]);
    final after = FunctionRewrite(
      before,
      replacements: {test: const Constant.boolean(false)},
    ).run();
    for (final function in [before, after]) {
      final program = IrProgram([], [function], externals: [IrExternal(_tick)]);
      final interpreter = IrInterpreter(program, {
        (_uri, 'tick'): (int _) => throw StateError('Unreachable call'),
      });
      expect(interpreter.run(function, []), 7);
    }
    expect(after.callees, isEmpty);
    expect(FunctionRewrite(after).run(), same(after));
  });

  test('known results preserve effects and exceptional continuations', () {
    final target = FunctionTarget(_uri, 'invoke', .integer, [.integer]);
    final entry = Block(target.parameterTypes),
        normal = Block([ValueType.integer]),
        caught = Block();
    final call = DirectCall(_tick, entry.parameters);
    entry.finish(
      Invoke(call, onReturn: Jump(normal, [call]), onThrow: Jump(caught)),
    );
    normal.finish(Return(normal.parameters.single));
    caught.finish(const Return(Constant.integer(-1)));
    final before = IrFunction(target, [entry, normal, caught]);
    final after = FunctionRewrite(
      before,
      replacements: {call: const Constant.integer(7)},
    ).run();
    for (final function in [before, after]) {
      final events = <int>[];
      final interpreter = IrInterpreter(
        IrProgram([], [function], externals: [IrExternal(_tick)]),
        {
          (_uri, 'tick'): (int input) {
            events.add(input);
            if (input < 0) throw StateError('failure');
            return 7;
          },
        },
      );
      expect(interpreter.run(function, [3]), 7);
      expect(interpreter.run(function, [-3]), -1);
      expect(events, [3, -3]);
    }
    expect(after.blocks.first.end, isA<Invoke>());
  });

  test('a collapsed type-test edge retains a valid refined operand', () {
    final target = FunctionTarget(_uri, 'refine', .integer, [.object]);
    final entry = Block(target.parameterTypes),
        yes = Block([ValueType.integer]),
        no = Block();
    final test = entry.emit(TypeTest(entry.parameters.single, .integer));
    entry.finish(Branch(test, Jump(yes, [test.refinement(true)!]), Jump(no)));
    yes.finish(Return(yes.parameters.single));
    no.finish(const Return(Constant.integer(-1)));
    final before = IrFunction(target, [entry, yes, no]);
    final after = FunctionRewrite(
      before,
      replacements: {test: const Constant.boolean(true)},
    ).run();
    expect(IrInterpreter(IrProgram([], [after]), {}).run(after, [42]), 42);
    expect(after.blocks, hasLength(2));
  });

  test('SSA substitution preserves identity, bounds and dominance', () {
    final target = FunctionTarget(_uri, 'alias', .integer, [.integer]);
    final entry = Block(target.parameterTypes);
    final sum = entry.emit(
      IntBinary(.add, entry.parameters.single, const Constant.integer(0)),
    );
    entry.finish(Return(sum));
    final function = IrFunction(target, [entry]);
    final rewritten = FunctionRewrite(
      function,
      replacements: {sum: entry.parameters.single},
    ).run();
    expect(rewritten.entry.instructions, isEmpty);
    expect(
      IrInterpreter(IrProgram([], [rewritten]), {}).run(rewritten, [42]),
      42,
    );
    final foreign = Block([ValueType.integer]).parameters.single;
    expect(
      () => FunctionRewrite(function, replacements: {sum: foreign}).run(),
      throwsArgumentError,
    );
    expect(
      () => FunctionRewrite(
        function,
        replacements: {
          sum: entry.parameters.single,
          entry.parameters.single: sum,
        },
      ).run(),
      throwsArgumentError,
    );

    final start = Block(target.parameterTypes),
        next = Block([ValueType.integer]);
    final late = next.emit(
      IntBinary(.add, next.parameters.single, const Constant.integer(0)),
    );
    start.finish(Jump(next, start.parameters));
    next.finish(Return(late));
    final dominated = IrFunction(target, [start, next]);
    expect(
      () => FunctionRewrite(
        dominated,
        replacements: {start.parameters.single: late},
      ).run(),
      throwsStateError,
    );
  });

  test(
    'dead loop-carried values disappear while their input effects remain',
    () {
      final target = FunctionTarget(_uri, 'loop', .integer, []);
      final entry = Block(),
          loop = Block([ValueType.integer, ValueType.integer]),
          done = Block();
      final input = entry.emit(DirectCall(_tick, [const Constant.integer(4)]));
      entry.finish(Jump(loop, [const Constant.integer(0), input]));
      final next = loop.emit(
        IntBinary(.add, loop.parameters[0], const Constant.integer(1)),
      );
      final wasted = loop.emit(
        IntBinary(.multiply, loop.parameters[1], const Constant.integer(123)),
      );
      final more = loop.emit(
        IntBinary(.lessThan, next, const Constant.integer(3)),
      );
      loop.finish(Branch(more, Jump(loop, [next, wasted]), Jump(done)));
      done.finish(Return(next));
      final before = IrFunction(target, [entry, loop, done]);
      final after = FunctionRewrite(before).run();
      for (final body in [before, after]) {
        final events = <int>[];
        final program = IrProgram([], [body], externals: [IrExternal(_tick)]);
        expect(
          IrInterpreter(program, {
            (_uri, 'tick'): (int value) {
              events.add(value);
              return value;
            },
          }).run(body, []),
          3,
        );
        expect(events, [4]);
      }
      expect(after.blocks[1].parameters, hasLength(1));
      expect(
        after.blocks
            .expand((block) => block.instructions)
            .whereType<IntBinary>()
            .map((operation) => operation.operator),
        isNot(contains(IntOperator.multiply)),
      );
      expect(FunctionRewrite(after).run(), same(after));
    },
  );

  test('await results and suspension stay valid after rebuilding', () async {
    final target = FunctionTarget(
      _uri,
      'suspend',
      CoreTypes.futureOf(.integer),
      [],
    );
    final entry = Block(), normal = Block([ValueType.integer]);
    entry.emit(
      IntBinary(.add, const Constant.integer(1), const Constant.integer(2)),
    );
    final result = AwaitResult(.integer);
    entry.finish(
      Await(
        const Constant.integer(7),
        result,
        onResume: Jump(normal, [result]),
      ),
    );
    normal.finish(Return(normal.parameters.single));
    final before = IrFunction(
      target,
      [entry, normal],
      bodyKind: .asynchronous,
      completionType: .integer,
    );
    final after = FunctionRewrite(before).run();
    expect(after, isNot(same(before)));
    for (final function in [before, after]) {
      final interpreter = IrInterpreter(IrProgram([], [function]), {});
      expect(await interpreter.resolveAsync(interpreter.run(function, [])), 7);
      expect(function.blocks.first.end, isA<Await>());
    }
  });

  test(
    'generator delegation and cancellation effects survive cleanup',
    () async {
      final stream = CoreTypes.streamOf(.integer);
      final target = FunctionTarget(_uri, 'events', stream, [stream]);
      final entry = Block(target.parameterTypes),
          delegate = Block(),
          cleanup = Block(),
          done = Block();
      entry.emit(
        IntBinary(.add, const Constant.integer(1), const Constant.integer(2)),
      );
      entry.finish(
        Yield(
          const Constant.integer(7),
          Jump(delegate),
          onCancel: Jump(cleanup),
        ),
      );
      delegate.finish(
        YieldStream(
          entry.parameters.single,
          Jump(cleanup),
          onCancel: Jump(cleanup),
        ),
      );
      cleanup.emit(DirectCall(_tick, [const Constant.integer(9)]));
      cleanup.finish(Jump(done));
      done.finish(const Return());
      final before = IrFunction(
        target,
        [entry, delegate, cleanup, done],
        bodyKind: .asyncGenerator,
        yieldType: .integer,
      );
      final after = FunctionRewrite(before).run();
      for (final function in [before, after]) {
        final events = <int>[];
        final interpreter = IrInterpreter(
          IrProgram([], [function], externals: [IrExternal(_tick)]),
          {
            (_uri, 'tick'): (int value) {
              events.add(value);
              return value;
            },
          },
        );
        Stream<Object?> run() => interpreter.run(function, [
          Stream<int>.fromIterable([8]),
        ]) as Stream<Object?>;
        expect(await run().toList(), [7, 8]);
        expect(events, [9]);
        events.clear();
        expect(await run().take(1).toList(), [7]);
        expect(events, [9]);
      }
    },
  );
}
