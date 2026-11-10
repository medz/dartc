import 'package:dartc/ir.dart';
import 'package:dartc/src/codegen/function_liveness.dart';
import 'package:dartc/src/codegen/function_representation.dart';
import 'package:dartc/src/codegen/program_layout.dart';
import 'package:test/test.dart';

void main() {
  final library = Uri.parse('memory:liveness');
  FunctionLiveness analyze(List<Block> blocks, ValueType result) {
    final target = FunctionTarget(
      library,
      'test',
      result,
      blocks.first.parameters.map((p) => p.type),
    );
    final body = FunctionRepresentation(
      IrFunction(target, blocks),
      ProgramLayout([]),
    );
    return FunctionLiveness(body, body.inputsOf, {
      ...body.boxes.keys,
      for (final block in body.blocks)
        for (final operation in body.instructions[block]!)
          if (operation is DirectCall || operation is NativeCall) operation,
    });
  }

  test('parallel edges map only the used target parameters', () {
    final entry = Block([.boolean, .object, .object, .object]);
    final join = Block([.object, .object]);
    final [condition, a, b, dead] = entry.parameters;
    entry.finish(
      Branch(condition, Jump(join, [a, dead]), Jump(join, [b, dead])),
    );
    join.finish(Return(join.parameters.first));
    final flow = analyze([entry, join], .object);
    expect(flow.liveParameters[join], [0]);
    expect(flow.liveIn[entry], {condition, a, b});
    expect(flow.liveOut[entry], {a, b});
    expect(flow.uses[entry], {condition: 1, a: 1, b: 1});
  });

  test(
    'invoke outcomes are created after the call and survive handler calls',
    () {
      for (final neverReturns in [false, true]) {
        final callee = FunctionTarget(
          library,
          'callee',
          neverReturns ? .never : .object,
          [.object],
        );
        final collect = FunctionTarget(library, 'collect', .voidType, []);
        final handle = FunctionTarget(library, 'handle', .object, [
          .object,
          .stackTrace,
          .object,
        ]);
        final entry = Block([.object, .object]);
        final success = neverReturns ? null : Block([.object]);
        final failure = Block([.object, .stackTrace]);
        final [keep, consumed] = entry.parameters;
        final call = DirectCall(callee, [consumed]);
        entry.finish(
          Invoke(
            call,
            onReturn: success == null ? null : Jump(success, [call]),
            onThrow: Jump(failure, [
              UnwindValue.exception,
              UnwindValue.stackTrace,
            ]),
          ),
        );
        success?.finish(Return(success.parameters.single));
        final nested = failure.emit(DirectCall(collect, []));
        failure.finish(
          Return(
            failure.emit(DirectCall(handle, [...failure.parameters, keep])),
          ),
        );

        final flow = analyze([entry, ?success, failure], .object);
        expect(flow.acrossCalls[call], {keep});
        expect(flow.acrossCalls[nested], {...failure.parameters, keep});
        expect(flow.liveIn[entry], {keep, consumed});
        expect(flow.liveOut[entry], {keep, if (!neverReturns) call});
      }
    },
  );

  test(
    'rethrow keeps the original pair and handler locals across prior calls',
    () {
      final entry = Block([.object, .stackTrace, .object]);
      final handler = Block([.object, .stackTrace, .object]);
      final collect = FunctionTarget(library, 'collect', .voidType, []);
      final call = entry.emit(DirectCall(collect, []));
      entry.finish(
        Throw(
          entry.parameters[0],
          stackTrace: entry.parameters[1],
          onThrow: Jump(handler, [
            UnwindValue.exception,
            UnwindValue.stackTrace,
            entry.parameters[2],
          ]),
        ),
      );
      final handle = FunctionTarget(
        library,
        'handle',
        .voidType,
        handler.parameters.map((p) => p.type),
      );
      handler.emit(DirectCall(handle, handler.parameters));
      handler.finish(const Return());

      final flow = analyze([entry, handler], .voidType);
      expect(flow.acrossCalls[call], entry.parameters.toSet());
      expect(flow.liveIn[entry], entry.parameters.toSet());
      expect(flow.liveOut[entry], {entry.parameters[2]});
    },
  );

  test(
    'a failed write retains old contents only when its handler reads them',
    () {
      for (final readsOldValue in [false, true]) {
        final entry = Block([.object, .object]),
            success = Block(),
            failure = Block();
        final [initial, replacement] = entry.parameters;
        final cell = entry.emit(
          NewCell(CellType(.object, isLate: true, isFinal: true), initial),
        );
        final collect = FunctionTarget(library, 'collect', .voidType, []);
        final call = entry.emit(DirectCall(collect, []));
        entry.finish(
          Invoke(
            WriteCell(cell, replacement),
            onReturn: Jump(success),
            onThrow: Jump(failure),
          ),
        );
        success.finish(Return(replacement));
        failure.finish(
          Return(readsOldValue ? failure.emit(ReadCell(cell)) : replacement),
        );

        final flow = analyze([entry, success, failure], .object);
        expect(flow.acrossCalls[call], {replacement, if (readsOldValue) cell});
      }
    },
  );

  test('a Never result is not a runtime operand of Unreachable', () {
    final entry = Block([.object]);
    final fail = FunctionTarget(library, 'fail', .never, [.object]);
    final call = entry.emit(DirectCall(fail, entry.parameters));
    entry.finish(Unreachable(call));
    final flow = analyze([entry], .never);
    expect(flow.liveIn[entry], entry.parameters.toSet());
    expect(flow.uses[entry], {entry.parameters.single: 1});
    expect(flow.acrossCalls[call], isEmpty);
  });

  test(
    'calls retain survivors, not results, consumed arguments or old locals',
    () {
      final callee = FunctionTarget(library, 'callee', .object, [.object]);
      final body = Block([.object, .object]);
      final cell = body.emit(NewCell(CellType(.object), body.parameters.first));
      final first = body.emit(DirectCall(callee, [body.parameters.last]));
      body.emit(WriteCell(cell, first));
      final second = body.emit(DirectCall(callee, [first]));
      body.finish(Return(body.emit(ReadCell(cell))));
      final flow = analyze([body], .object);
      expect(flow.acrossCalls[first], isEmpty);
      expect(flow.acrossCalls[second], {cell});
    },
  );

  test('scrambled loops propagate swaps without retaining dead cycles', () {
    final entry = Block([.object, .object, .integer, .object]);
    final loop = Block(entry.parameters.map((p) => p.type));
    final again = Block(), done = Block();
    final [a, b, count, dead] = loop.parameters;
    entry.finish(Jump(loop, entry.parameters));
    loop.finish(
      Branch(
        loop.emit(IntBinary(.greaterThan, count, const Constant.integer(0))),
        Jump(again),
        Jump(done),
      ),
    );
    final decrement = again.emit(
      IntBinary(.subtract, count, const Constant.integer(1)),
    );
    again.finish(Jump(loop, [b, a, decrement, dead]));
    done.finish(Return(a));
    final flow = analyze([entry, done, again, loop], .object);
    expect(flow.liveParameters[loop], [0, 1, 2]);
    expect(flow.liveIn[loop], {a, b, count});
    expect(flow.liveIn[again], {a, b, count});
    expect(flow.liveOut[again], {a, b, decrement});
    expect(flow.liveIn[done], {a});
    expect(flow.liveParameters[entry], [0, 1, 2]);
  });

  test('refinements keep the original storage alive on the selected edge', () {
    final entry = Block([ValueType.integer.nullable]);
    final yes = Block([.integer]), no = Block();
    final original = entry.parameters.single;
    final check = entry.emit(TypeTest(original, .integer));
    final refinement = check.refinement(true)!;
    entry.finish(Branch(check, Jump(yes, [refinement]), Jump(no)));
    yes.finish(Return(yes.parameters.single));
    no.finish(Return(const Constant.integer(0)));
    final flow = analyze([entry, yes, no], .integer);
    expect(flow.liveOut[entry], {original});
    expect(flow.uses[entry], {original: 2, check: 1});
    expect(flow.liveIn[yes], {yes.parameters.single});
    expect(flow.liveIn[no], isEmpty);
  });

  test(
    'overwriting a local kills its previous contents, not the written value',
    () {
      final entry = Block([ValueType.object.nullable]);
      final write = Block(), read = Block();
      final cell = entry.emit(
        NewCell(
          CellType(ValueType.object.nullable),
          const Constant.nullValue(),
        ),
      );
      entry.finish(Jump(write));
      write.emit(WriteCell(cell, entry.parameters.single));
      write.finish(Jump(read));
      read.finish(Return(read.emit(ReadCell(cell))));
      final flow = analyze([entry, write, read], ValueType.object.nullable);
      expect(flow.liveIn[write], {entry.parameters.single});
      expect(flow.liveOut[write], {cell});
      expect(flow.liveIn[read], {cell});
      expect(flow.uses[write], {entry.parameters.single: 1});
    },
  );
}
