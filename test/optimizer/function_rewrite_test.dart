import 'package:dartc/ir.dart';
import 'package:dartc/src/optimizer/function_rewrite.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

final _uri = Uri.parse('memory:rewrite');
final _tick = FunctionTarget(_uri, 'tick', .integer, [.integer]);

void main() {
  test(
    'replacement terminators preserve operand effects, handlers and origins',
    () {
      final target = FunctionTarget(_uri, 'recorded', .stackTrace, [
        .integer,
        .stackTrace,
      ]);
      final guard = FunctionTarget(_uri, 'guard', .voidType, [
        .object,
        .stackTrace,
      ]);
      final entry = Block(target.parameterTypes),
          caught = Block([.object, .stackTrace]);
      final operand = entry.emit(DirectCall(_tick, [entry.parameters.first]));
      final trace = entry.parameters.last;
      final handler = Jump(caught, [
        UnwindValue.exception,
        UnwindValue.stackTrace,
      ]);
      entry.finish(Throw(operand, stackTrace: trace, onThrow: handler));
      caught.finish(Return(caught.parameters.last));
      final location = SourceLocation((uri: _uri, line: 7, column: 3));
      final original = IrFunction(
        target,
        [entry, caught],
        sourceLocations: {entry: location},
      );
      final done = Block()
        ..finish(Throw.recorded(operand, trace, onThrow: handler));
      final call = DirectCall(guard, [operand, trace]);
      final rewritten = FunctionRewrite(
        original,
        terminators: {
          entry: Invoke(call, onReturn: Jump(done), onThrow: handler),
        },
      ).run();
      final supplied = StackTrace.fromString('supplied');
      final failed = StackTrace.fromString('guard failed');
      final effects = <Object>[];
      final runner = IrInterpreter(
        IrProgram([], [rewritten]),
        {
          (_uri, 'tick'): (int value) {
            effects.add(value);
            return value + 1;
          },
        },
        externalCalls: {
          guard: (arguments) {
            final value = arguments.first as int;
            effects.add(('guard', value));
            if (value < 0) Error.throwWithStackTrace('failed', failed);
            return null;
          },
        },
      );
      for (final value in [-7, 0, 23]) {
        expect(
          runner.run(rewritten, [value, supplied]),
          same(value < -1 ? failed : supplied),
        );
        expect(effects, [value, ('guard', value + 1)]);
        effects.clear();
      }
      final normalized = rewritten.blocks.singleWhere(
        (block) => block.end is Throw,
      );
      expect((normalized.end as Throw).isRecorded, isTrue);
      expect(rewritten.sourceLocations[normalized], location);
      final invocation = rewritten.blocks
          .map((block) => block.end)
          .whereType<Invoke>()
          .single;
      expect(rewritten.sourceLocations[invocation.operation], location);
      final text = StringBuffer();
      rewritten.writeTo(text);
      expect(text.toString(), contains('throw.recorded'));
      expect(
        () => FunctionRewrite(
          original,
          terminators: {Block(): const Return()},
        ).run(),
        throwsArgumentError,
      );
      expect(
        () => FunctionRewrite(
          original,
          terminators: {
            entry: Return(Block([.stackTrace]).parameters.single),
          },
        ).run(),
        throwsStateError,
      );
      expect(
        () => Throw.recorded(operand, const Constant.nullValue()),
        throwsArgumentError,
      );
    },
  );

  test('inlining retains recorded throws and the caller handler', () {
    final helper = FunctionTarget(_uri, 'raise', .never, [
      .object,
      .stackTrace,
    ]);
    final body = Block(helper.parameterTypes);
    body.finish(Throw.recorded(body.parameters.first, body.parameters.last));
    final callee = IrFunction(helper, [body]);
    final target = FunctionTarget(
      _uri,
      'catchRecorded',
      .object,
      helper.parameterTypes,
    );
    final entry = Block(target.parameterTypes), caught = Block([.object]);
    final call = DirectCall(helper, entry.parameters);
    final handler = Jump(caught, [UnwindValue.exception]);
    entry.finish(Invoke(call, onReturn: null, onThrow: handler));
    caught.finish(Return(caught.parameters.single));
    final source = IrFunction(target, [entry, caught]);
    final rewritten = FunctionRewrite(
      source,
      inlined: {
        call: (
          body: callee,
          arguments: entry.parameters,
          environment: <TypeParameterType, ValueType>{},
          handler: handler,
        ),
      },
    ).run();
    final throwing = rewritten.blocks
        .map((block) => block.end)
        .whereType<Throw>()
        .single;
    expect(throwing.isRecorded, isTrue);
    expect(throwing.onThrow, isNotNull);
    final runner = IrInterpreter(IrProgram([], [rewritten]), {});
    for (final error in [7, 'error', Object()]) {
      expect(runner.run(rewritten, [error, StackTrace.empty]), same(error));
    }
  });

  test('constant incoming branches preserve parallel parameter swaps', () {
    final target = FunctionTarget(_uri, 'swapped', .integer, [
      .integer,
      .integer,
      .boolean,
    ]);
    final entry = Block(target.parameterTypes);
    final dispatch = Block([.boolean, .integer, .integer]);
    final done = Block([.integer, .integer]);
    entry.finish(
      Branch(
        entry.parameters[2],
        Jump(dispatch, [
          const Constant.boolean(true),
          ...entry.parameters.take(2),
        ]),
        Jump(dispatch, [
          const Constant.boolean(false),
          ...entry.parameters.take(2),
        ]),
      ),
    );
    dispatch.finish(
      Branch(
        dispatch.parameters[0],
        Jump(done, [dispatch.parameters[2], dispatch.parameters[1]]),
        Jump(done, [dispatch.parameters[1], dispatch.parameters[2]]),
      ),
    );
    done.finish(
      Return(
        done.emit(IntBinary(.subtract, done.parameters[0], done.parameters[1])),
      ),
    );
    final before = IrFunction(target, [entry, dispatch, done]);
    final after = FunctionRewrite(before).run();
    expect(
      after.blocks.map((block) => block.end).whereType<Branch>(),
      hasLength(1),
    );
    for (final function in [before, after]) {
      final runner = IrInterpreter(IrProgram([], [function]), {});
      expect(runner.run(function, [7, 2, true]), -5);
      expect(runner.run(function, [7, 2, false]), 5);
    }
  });

  test(
    'threading preserves effects and bindings used by descendant blocks',
    () {
      for (final effectful in [false, true]) {
        final target = FunctionTarget(_uri, 'retained', .integer, [
          .integer,
          .integer,
          .boolean,
        ]);
        final entry = Block(target.parameterTypes);
        final dispatch = Block([.boolean, .integer]);
        final yes = Block(effectful ? [.integer] : []);
        final no = Block(effectful ? [.integer] : []);
        entry.finish(
          Branch(
            entry.parameters[2],
            Jump(dispatch, [const Constant.boolean(true), entry.parameters[0]]),
            Jump(dispatch, [
              const Constant.boolean(false),
              entry.parameters[1],
            ]),
          ),
        );
        if (effectful) {
          dispatch.emit(DirectCall(_tick, [dispatch.parameters[1]]));
        }
        dispatch.finish(
          Branch(
            dispatch.parameters[0],
            Jump(yes, effectful ? [dispatch.parameters[1]] : []),
            Jump(no, effectful ? [dispatch.parameters[1]] : []),
          ),
        );
        yes.finish(
          Return(effectful ? yes.parameters.single : dispatch.parameters[1]),
        );
        no.finish(
          Return(
            no.emit(
              IntBinary(
                .add,
                effectful ? no.parameters.single : dispatch.parameters[1],
                const Constant.integer(100),
              ),
            ),
          ),
        );
        final before = IrFunction(target, [entry, dispatch, yes, no]);
        final after = FunctionRewrite(before).run();
        for (final function in [before, after]) {
          final events = <int>[];
          final runner = IrInterpreter(
            IrProgram([], [function], externals: [IrExternal(_tick)]),
            {
              (_uri, 'tick'): (value) {
                events.add(value);
                return value;
              },
            },
          );
          expect(runner.run(function, [7, 2, true]), 7);
          expect(runner.run(function, [7, 2, false]), 102);
          expect(events, effectful ? [7, 2] : isEmpty);
        }
      }
    },
  );

  test('empty control cycles preserve their changing branch arguments', () {
    final target = FunctionTarget(_uri, 'cycle', .integer, [
      .integer,
      .integer,
      .boolean,
    ]);
    final entry = Block(target.parameterTypes);
    final first = Block([.boolean, .integer, .integer]);
    final second = Block([.boolean, .integer, .integer]);
    final done = Block([.integer, .integer]);
    entry.finish(
      Jump(first, [entry.parameters[2], ...entry.parameters.take(2)]),
    );
    first.finish(
      Jump(second, [
        first.parameters[0],
        first.parameters[2],
        first.parameters[1],
      ]),
    );
    second.finish(
      Branch(
        second.parameters[0],
        Jump(first, [
          const Constant.boolean(false),
          ...second.parameters.skip(1),
        ]),
        Jump(done, second.parameters.skip(1)),
      ),
    );
    done.finish(
      Return(
        done.emit(IntBinary(.subtract, done.parameters[0], done.parameters[1])),
      ),
    );
    final before = IrFunction(target, [entry, first, second, done]);
    final after = FunctionRewrite(before).run();
    final repeated = FunctionRewrite(after).run();
    for (final function in [before, after, repeated]) {
      final runner = IrInterpreter(IrProgram([], [function]), {});
      expect(runner.run(function, [7, 2, true]), 5);
      expect(runner.run(function, [7, 2, false]), -5);
    }
  });

  test(
    'inlined entry arguments must dominate the call and match its types',
    () {
      final calleeEntry = Block(_tick.parameterTypes);
      calleeEntry.finish(Return(calleeEntry.parameters.single));
      final callee = IrFunction(_tick, [calleeEntry]);
      final target = FunctionTarget(_uri, 'entry', .integer, [.integer]);
      final entry = Block(target.parameterTypes);
      final call = entry.emit(DirectCall(_tick, entry.parameters));
      final later = entry.emit(
        IntBinary(.add, call, const Constant.integer(1)),
      );
      entry.finish(Return(later));
      final function = IrFunction(target, [entry]);
      for (final arguments in [
        [later],
        [const Constant.string('wrong type')],
        <Value>[],
      ]) {
        expect(
          () => FunctionRewrite(
            function,
            inlined: {
              call: (
                body: callee,
                arguments: arguments,
                environment: const {},
                handler: null,
              ),
            },
          ).run(),
          throwsArgumentError,
        );
      }
    },
  );

  test('inlining cannot move a live call-frame argument into another call', () {
    final observe = FunctionTarget(_uri, 'observeFrame', .integer, [.integer]);
    final callee = FunctionTarget(_uri, 'frame', .integer, [.integer]);
    final body = Block(callee.parameterTypes);
    body.finish(Return(body.emit(DirectCall(observe, body.parameters))));
    final function = IrFunction(callee, [body]);
    final root = FunctionTarget(_uri, 'root', .integer, []);
    final entry = Block();
    final call = entry.emit(DirectCall(callee, [CallFrameValue.stackPointer]));
    entry.finish(Return(call));
    expect(
      () => FunctionRewrite(
        IrFunction(root, [entry]),
        inlined: {
          call: (
            body: function,
            arguments: call.inputs,
            environment: const {},
            handler: null,
          ),
        },
      ).run(),
      throwsArgumentError,
    );
  });

  test('fresh pure call inputs keep their evaluation and exception point', () {
    final target = FunctionTarget(_uri, 'templated', .integer, [.object]);
    final entry = Block(target.parameterTypes);
    final normal = Block([ValueType.integer]), caught = Block();
    final original = entry.emit(
      UncheckedCast(entry.parameters.single, .integer),
    );
    final call = DirectCall(_tick, [original]);
    entry.finish(
      Invoke(call, onReturn: Jump(normal, [call]), onThrow: Jump(caught)),
    );
    normal.finish(Return(normal.parameters.single));
    caught.finish(const Return(Constant.integer(-1)));
    final before = IrFunction(target, [entry, normal, caught]);
    final after = FunctionRewrite(
      before,
      operations: {
        call: DirectCall(_tick, [
          UncheckedCast(
            TypeView(entry.parameters.single, .object.nullable),
            .integer,
          ),
        ]),
      },
    ).run();
    for (final function in [before, after]) {
      final events = <int>[];
      final interpreter = IrInterpreter(
        IrProgram([], [function], externals: [IrExternal(_tick)]),
        {
          (_uri, 'tick'): (int value) {
            events.add(value);
            if (value < 0) throw StateError('negative');
            return value;
          },
        },
      );
      expect(interpreter.run(function, [7]), 7);
      expect(interpreter.run(function, [-2]), -1);
      expect(events, [7, -2]);
    }
    expect(
      () => FunctionRewrite(
        before,
        operations: {
          call: DirectCall(_tick, [
            TypeCast(entry.parameters.single, .integer),
          ]),
        },
      ).run(),
      throwsArgumentError,
    );
  });

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

  test('discardable retained invokes keep their failure region', () {
    for (final observed in [false, true]) {
      final target = FunctionTarget(_uri, 'allocation', .integer, [.integer]);
      final entry = Block(target.parameterTypes),
          normal = Block([ValueType.integer]),
          caught = Block();
      final call = DirectCall(_tick, entry.parameters);
      entry.finish(
        Invoke(call, onReturn: Jump(normal, [call]), onThrow: Jump(caught)),
      );
      normal.finish(
        Return(observed ? normal.parameters.single : const Constant.integer(7)),
      );
      caught.finish(const Return(Constant.integer(-1)));
      final before = IrFunction(target, [entry, normal, caught]);
      final after = FunctionRewrite(before, discardable: {call}).run();
      final events = <int>[];
      final interpreter = IrInterpreter(
        IrProgram([], [after], externals: [IrExternal(_tick)]),
        {},
        externalCalls: {
          _tick: (arguments) {
            final value = arguments.single as int;
            events.add(value);
            if (value < 0) throw StateError('allocation');
            return value;
          },
        },
      );
      expect(interpreter.run(after, [-3]), observed ? -1 : 7);
      expect(interpreter.run(after, [42]), observed ? 42 : 7);
      expect(events, observed ? [-3, 42] : isEmpty);
    }
  });

  test(
    'direct local throws retain operand effects and reject foreign proofs',
    () {
      final target = FunctionTarget(_uri, 'localThrow', .integer, [.integer]);
      final entry = Block(target.parameterTypes), handler = Block([.object]);
      final operand = entry.emit(DirectCall(_tick, entry.parameters));
      final throwing = Throw(
        operand,
        onThrow: Jump(handler, [UnwindValue.exception]),
      );
      entry.finish(throwing);
      handler.finish(
        Return(
          handler.emit(UncheckedCast(handler.parameters.single, .integer)),
        ),
      );
      final original = IrFunction(target, [entry, handler]);
      final rewritten = FunctionRewrite(
        original,
        directThrows: {throwing},
      ).run();
      for (final body in [original, rewritten]) {
        final observed = <int>[];
        final runner = IrInterpreter(IrProgram([], [body]), {
          (_uri, 'tick'): (input) {
            observed.add(input);
            if (input < 0) throw StateError('operand failed');
            return input + 1;
          },
        });
        expect(runner.run(body, [7]), 8);
        expect(() => runner.run(body, [-2]), throwsStateError);
        expect(observed, [7, -2]);
      }
      expect(rewritten.blocks.map((b) => b.end).whereType<Throw>(), isEmpty);
      final other = Throw(
        operand,
        onThrow: Jump(handler, [UnwindValue.exception]),
      );
      expect(
        () => FunctionRewrite(original, directThrows: {other}).run(),
        throwsArgumentError,
      );
      final escaping = Block(target.parameterTypes);
      final uncaught = Throw(escaping.parameters.single);
      escaping.finish(uncaught);
      expect(
        () => FunctionRewrite(
          IrFunction(target, [escaping]),
          directThrows: {uncaught},
        ).run(),
        throwsArgumentError,
      );
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

  test('inlined throwing type tests narrow only their successful edge', () {
    final calleeTarget = FunctionTarget(_uri, 'narrow', .integer, [
      .object.nullable,
    ]);
    final entry = Block(calleeTarget.parameterTypes),
        yes = Block([ValueType.integer]),
        no = Block();
    final test = entry.emit(TypeTest(entry.parameters.single, .integer));
    entry.finish(Branch(test, Jump(yes, [test.refinement(true)!]), Jump(no)));
    yes.finish(Return(yes.parameters.single));
    no.finish(Throw(const Constant.string('wrong type')));
    final callee = IrFunction(calleeTarget, [entry, yes, no]);
    final target = FunctionTarget(_uri, 'caller', .integer, [.object.nullable]);
    final start = Block(target.parameterTypes),
        returned = Block([ValueType.integer]),
        caught = Block([.object, .stackTrace]);
    final call = DirectCall(calleeTarget, start.parameters);
    final handler = Jump(caught, [
      UnwindValue.exception,
      UnwindValue.stackTrace,
    ]);
    start.finish(
      Invoke(call, onReturn: Jump(returned, [call]), onThrow: handler),
    );
    returned.finish(Return(returned.parameters.single));
    caught.finish(const Return(Constant.integer(-1)));
    final before = IrFunction(target, [start, returned, caught]);
    final after = FunctionRewrite(
      before,
      inlined: {
        call: (
          body: callee,
          arguments: start.parameters,
          environment: const {},
          handler: handler,
        ),
      },
    ).run();
    for (final function in [before, after]) {
      final interpreter = IrInterpreter(IrProgram([], [function, callee]), {});
      expect(interpreter.run(function, [41]), 41);
      expect(interpreter.run(function, ['wrong']), -1);
      expect(interpreter.run(function, [null]), -1);
    }
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
