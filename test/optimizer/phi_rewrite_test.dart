import 'package:dartc/ir.dart';
import 'package:dartc/src/optimizer/function_rewrite.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

final _uri = Uri.parse('memory:phi-rewrite');
const _one = Constant.integer(1);

void main() {
  test('field-free branch values replace a shared cell through a phi', () {
    final target = FunctionTarget(_uri, 'select', .integer, [
      .boolean,
      .integer,
      .integer,
    ]);
    final entry = Block(target.parameterTypes),
        left = Block(),
        right = Block(),
        done = Block();
    final cell = entry.emit(NewCell(CellType(.integer), entry.parameters[1]));
    entry.finish(Branch(entry.parameters[0], Jump(left), Jump(right)));
    final a = left.emit(IntBinary(.add, entry.parameters[1], _one));
    final writeA = left.emit(WriteCell(cell, a));
    final fromA = Jump(done);
    left.finish(fromA);
    final b = right.emit(
      IntBinary(.multiply, entry.parameters[2], const Constant.integer(2)),
    );
    final writeB = right.emit(WriteCell(cell, b));
    final fromB = Jump(done);
    right.finish(fromB);
    final read = done.emit(ReadCell(cell));
    done.finish(Return(read));
    final source = IrFunction(target, [entry, left, right, done]);
    final phi = blockParameters([ValueType.integer]).single;
    final rewritten = FunctionRewrite(
      source,
      phis: {
        phi: (block: done, incoming: {fromA: a, fromB: b}),
      },
      replacements: {read: phi},
      discardable: {cell, writeA, writeB, read},
    ).run();
    for (final args in [
      [true, 3, 5],
      [false, 3, 5],
      [false, -2, -4],
    ]) {
      expect(_run(rewritten, args), _run(source, args));
    }
    expect(
      rewritten.blocks
          .expand((b) => b.instructions)
          .where((i) => i is NewCell || i is ReadCell || i is WriteCell),
      isEmpty,
    );
    final dominance = ValueDominance(source);
    expect(dominance.onEdge(a, fromA), isTrue);
    expect(dominance.onEdge(a, fromB), isFalse);
    expect(dominance.before(a, read), isFalse);
    expect(dominance.atEntry(entry.parameters[1], done), isTrue);
    expect(dominance.before(entry.parameters[1], a), isTrue);
    expect(
      dominance.before(Block([ValueType.integer]).parameters.single, a),
      isFalse,
    );
    expect(FunctionRewrite(rewritten).run(), same(rewritten));
    expect(
      () => FunctionRewrite(
        source,
        phis: {
          phi: (block: done, incoming: {fromA: a}),
        },
        replacements: {read: phi},
      ).run(),
      throwsArgumentError,
    );
    expect(
      () => FunctionRewrite(
        source,
        phis: {
          phi: (block: done, incoming: {fromA: a, fromB: a}),
        },
        replacements: {read: phi},
        discardable: {read},
      ).run(),
      throwsStateError,
    );
  });

  test(
    'a cyclic phi preserves loop-carried values and the zero-iteration exit',
    () {
      final target = FunctionTarget(_uri, 'sum', .integer, [
        .integer,
        .integer,
      ]);
      final entry = Block(target.parameterTypes),
          loop = Block([ValueType.integer]),
          body = Block(),
          done = Block();
      final cell = entry.emit(NewCell(CellType(.integer), entry.parameters[1]));
      final start = Jump(loop, [const Constant.integer(0)]);
      entry.finish(start);
      final test = loop.emit(
        IntBinary(.lessThan, loop.parameters.single, entry.parameters[0]),
      );
      loop.finish(Branch(test, Jump(body), Jump(done)));
      final prior = body.emit(ReadCell(cell));
      final sum = body.emit(IntBinary(.add, prior, loop.parameters.single));
      final write = body.emit(WriteCell(cell, sum));
      final next = body.emit(IntBinary(.add, loop.parameters.single, _one));
      final back = Jump(loop, [next]);
      body.finish(back);
      final result = done.emit(ReadCell(cell));
      done.finish(Return(result));
      final source = IrFunction(target, [entry, loop, body, done]);
      final phi = blockParameters([ValueType.integer]).single;
      final rewritten = FunctionRewrite(
        source,
        phis: {
          phi: (block: loop, incoming: {start: entry.parameters[1], back: sum}),
        },
        replacements: {prior: phi, result: phi},
        discardable: {cell, prior, write, result},
      ).run();
      for (final args in [
        [0, 7],
        [1, 7],
        [5, -2],
      ]) {
        expect(_run(rewritten, args), _run(source, args));
      }
      expect(
        rewritten.blocks.expand((b) => b.instructions).whereType<NewCell>(),
        isEmpty,
      );
      expect(ValueDominance(source).onEdge(sum, back), isTrue);
      expect(ValueDominance(source).onEdge(sum, start), isFalse);
    },
  );

  test(
    'operation templates retain narrower static results without a wrapper',
    () {
      final broad = FunctionTarget(_uri, 'broad', .object, []);
      final target = FunctionTarget(_uri, 'narrow', .object, []);
      final entry = Block();
      final call = entry.emit(DirectCall(broad, []));
      entry.finish(Return(call));
      final source = IrFunction(target, [entry]);
      final rewritten = FunctionRewrite(
        source,
        operations: {
          call: IntBinary(
            .add,
            const Constant.integer(3),
            const Constant.integer(4),
          ),
        },
      ).run();
      expect(_run(rewritten, []), 7);
      expect((rewritten.entry.end as Return).value!.type, ValueType.integer);
      expect(rewritten.entry.instructions.whereType<TypeView>(), isEmpty);
    },
  );

  test('normal-result phis retain the independent exceptional edge', () {
    final tick = FunctionTarget(_uri, 'tick', .integer, [.integer]);
    final target = FunctionTarget(_uri, 'invoke', .integer, [.integer]);
    final entry = Block(target.parameterTypes),
        normal = Block([ValueType.integer]),
        caught = Block();
    final call = DirectCall(tick, entry.parameters);
    final returned = Jump(normal, [call]), failed = Jump(caught);
    entry.finish(Invoke(call, onReturn: returned, onThrow: failed));
    normal.finish(Return(normal.parameters.single));
    caught.finish(const Return(Constant.integer(-1)));
    final source = IrFunction(target, [entry, normal, caught]);
    final phi = blockParameters([ValueType.integer]).single;
    final rewritten = FunctionRewrite(
      source,
      phis: {
        phi: (block: normal, incoming: {returned: call}),
      },
      replacements: {normal.parameters.single: phi},
    ).run();
    final dominance = ValueDominance(source);
    expect(dominance.onEdge(call, returned), isTrue);
    expect(dominance.onEdge(call, failed), isFalse);
    expect(dominance.atEntry(call, normal), isFalse);
    expect(dominance.onEdge(UnwindValue.exception, failed), isTrue);
    expect(dominance.onEdge(UnwindValue.exception, returned), isFalse);
    for (final function in [source, rewritten]) {
      final events = <int>[];
      final interpreter = IrInterpreter(
        IrProgram([], [function], externals: [IrExternal(tick)]),
        {
          (_uri, 'tick'): (int value) {
            events.add(value);
            if (value < 0) throw StateError('failed');
            return value + 1;
          },
        },
      );
      expect(interpreter.run(function, [4]), 5);
      expect(interpreter.run(function, [-4]), -1);
      expect(events, [4, -4]);
    }
  });

  test(
    'operation templates retain their inputs, effects and error handler',
    () {
      final tick = FunctionTarget(_uri, 'tick', .integer, [.integer]);
      final lowered = FunctionTarget(_uri, 'lowered', .integer, [.integer]);
      final target = FunctionTarget(_uri, 'invoke', .integer, [.integer]);
      final entry = Block(target.parameterTypes),
          normal = Block([ValueType.integer]),
          caught = Block();
      final input = entry.emit(
        IntBinary(.add, entry.parameters.single, const Constant.integer(0)),
      );
      final call = DirectCall(tick, entry.parameters);
      entry.finish(
        Invoke(call, onReturn: Jump(normal, [call]), onThrow: Jump(caught)),
      );
      normal.finish(Return(normal.parameters.single));
      caught.finish(const Return(Constant.integer(-1)));
      final location = SourceLocation((uri: _uri, line: 12, column: 3));
      final source = IrFunction(
        target,
        [entry, normal, caught],
        sourceLocations: {call: location},
      );
      final rewritten = FunctionRewrite(
        source,
        operations: {
          call: DirectCall(lowered, [input]),
        },
      ).run();
      for (final function in [source, rewritten]) {
        final events = <int>[];
        int effect(int value) {
          events.add(value);
          if (value < 0) throw StateError('failed');
          return value + 1;
        }

        final interpreter = IrInterpreter(
          IrProgram(
            [],
            [function],
            externals: [IrExternal(tick), IrExternal(lowered)],
          ),
          {(_uri, 'tick'): effect, (_uri, 'lowered'): effect},
        );
        expect(interpreter.run(function, [4]), 5);
        expect(interpreter.run(function, [-4]), -1);
        expect(events, [4, -4]);
      }
      final replacement = (rewritten.entry.end as Invoke).operation;
      expect(rewritten.sourceLocations[replacement], same(location));
      expect(rewritten.entry.instructions.whereType<IntBinary>(), hasLength(1));
      expect((replacement as DirectCall).target, lowered);
      expect(
        () => FunctionRewrite(
          source,
          operations: {
            call: DirectCall(lowered, [call]),
          },
        ).run(),
        throwsArgumentError,
      );
      expect(
        () => FunctionRewrite(
          source,
          operations: {
            call: DirectCall(lowered, Block([ValueType.integer]).parameters),
          },
        ).run(),
        throwsArgumentError,
      );
    },
  );
}

Object? _run(IrFunction function, List<Object> arguments) =>
    IrInterpreter(IrProgram([], [function]), {}).run(function, arguments);
