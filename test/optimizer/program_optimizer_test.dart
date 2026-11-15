import 'dart:ffi' show Abi, Int32, Int64, Uint8;

import 'package:dartc/abi.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/target.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

final _uri = Uri.parse('memory:program-optimizer');

void main() {
  test(
    'lowering waits for semantic convergence without renewing pass budgets',
    () {
      final root = FunctionTarget(_uri, 'phase', .integer, []);
      IrProgram returning(int value) => IrProgram([], [
        IrFunction(root, [Block()..finish(Return(Constant.integer(value)))]),
      ]);
      var expansions = 0, lowerings = 0;
      final observations = <int>[];
      final optimizer = ProgramOptimizer([
        _Phase(.lowering, () {
          lowerings++;
          var changed = false;
          return ProgramTransform((facts) {
            observations.add(
              (facts.returnedBy(root).constant as ScalarConstant).value as int,
            );
            if (changed) return facts.program;
            changed = true;
            return returning(20);
          });
        }),
        _Phase(.expansion, () {
          expansions++;
          var remaining = 2;
          return ProgramTransform((facts) {
            if (remaining == 0) return facts.program;
            remaining--;
            final value =
                (facts.returnedBy(root).constant as ScalarConstant).value
                    as int;
            return returning(value - 1);
          });
        }),
      ]);
      for (var compilation = 1; compilation <= 2; compilation++) {
        observations.clear();
        final result = optimizer.run(returning(2), [
          (target: root, arguments: []),
        ]);
        expect(observations, [0, 20]);
        expect(expansions, compilation);
        expect(lowerings, compilation);
        expect((result.returnedBy(root).constant as ScalarConstant).value, 20);
      }
    },
  );

  test(
    'native layout facts follow the output ABI before program rewriting',
    () {
      final word = NativeAbiIntegerType(_uri, 'Word', {
        Abi.macosArm64: NativeScalarType(Int64),
        Abi.linuxX64: NativeScalarType(Int32),
      });
      final pair = NativeCompoundType('Pair', [
        NativeField('tag', NativeScalarType(Uint8)),
        NativeField('value', word),
      ]);
      final root = FunctionTarget(_uri, 'layout', .integer, []);
      final entry = Block();
      entry.finish(
        Return(
          entry.emit(
            IntBinary(
              .add,
              entry.emit(NativeSize(NativeArrayType(pair, 3))),
              entry.emit(NativeFieldOffset(pair, 1)),
            ),
          ),
        ),
      );
      final program = IrProgram([], [
        IrFunction(root, [entry]),
      ]);
      final optimizer = ProgramOptimizer(const [ProgramSimplification()]);
      final entries = [(target: root, arguments: <FlowValue>[])];
      expect(optimizer.run(program, entries).returnedBy(root).constant, isNull);
      for (final (target, expected) in [
        (const Target(.macos, .arm64), 56),
        (const Target(.linux, .x64), 28),
      ]) {
        final facts = optimizer.run(
          program,
          entries,
          memoryLayoutFor: (graph) => _Layout(graph, target: target),
        );
        final body = facts.program.implementationOf(root) as IrFunction;
        expect(IrInterpreter(facts.program, {}).run(body, []), expected);
      }
      expect(
        () => optimizer.run(program, entries, memoryLayoutFor: _Layout.new),
        throwsUnsupportedError,
      );
    },
  );

  test('rewritten storage is analyzed using the new graph layout', () {
    final storage = ClassType(null, 'Payload');
    final root = FunctionTarget(null, 'read', .integer, []);
    final block = Block();
    final object = block.emit(NewPayload(storage, const Constant.integer(8)));
    final address = block.emit(
      IntBinary(
        .add,
        block.emit(ReferenceAddress(object)),
        Constant.integer(ObjectLayout([]).size + 8),
      ),
    );
    final read = block.emit(LoadNative(address, NativeScalarType(Uint8)));
    block.finish(Return(read));
    final program = IrProgram(
      [IrClass(storage, [])],
      [
        IrFunction(root, [block]),
      ],
    );
    final entries = [(target: root, arguments: <FlowValue>[])];
    final original = ProgramOptimizer(const [])
        .run(program, entries, memoryLayoutFor: _Layout.new);
    expect(original.valueOf(read).constant, isNull);
    final changed = ProgramOptimizer([_AddField()])
        .run(program, entries, memoryLayoutFor: _Layout.new);
    expect(
      changed.valueOf(read).constant?.structuralKey,
      const Constant.integer(0).structuralKey,
    );
    expect(() => original.checkProgram(changed.program), throwsArgumentError);
  });

  test('shrinking calls frees space within a compilation size limit', () {
    final step = FunctionTarget(_uri, 'step', .integer, [.integer]);
    final body = Block(step.parameterTypes);
    body.finish(
      Return(
        body.emit(
          IntBinary(.add, body.parameters.single, const Constant.integer(1)),
        ),
      ),
    );
    final root = FunctionTarget(_uri, 'root', .integer, [.integer]);
    final entry = Block(root.parameterTypes);
    Value value = entry.parameters.single;
    for (var i = 0; i < 3; i++) {
      value = entry.emit(DirectCall(step, [value]));
    }
    entry.finish(Return(value));
    final program = IrProgram([], [
      IrFunction(step, [body]),
      IrFunction(root, [entry]),
    ]);
    final optimizer = ProgramOptimizer(const [
      ProgramSimplification(),
      DirectCallInlining(maxCallerGrowth: 1),
    ]);
    for (var compilation = 0; compilation < 2; compilation++) {
      final result = optimizer.run(program, const [], openEntries: [root]);
      final rewritten = result.program.implementationOf(root) as IrFunction;
      expect(
        rewritten.blocks
            .expand((block) => block.instructions)
            .whereType<DirectCall>(),
        isEmpty,
      );
      expect(
        rewritten.blocks.expand((block) => block.instructions),
        hasLength(3),
      );
      for (final input in [-2, 0, 41]) {
        expect(
          IrInterpreter(result.program, {}).run(rewritten, [input]),
          input + 3,
        );
      }
    }
  });

  test('actual call arguments remove dead dependencies without inlining', () {
    final equals = FunctionTarget(_uri, 'equals', .boolean, [
      .integer,
      .integer,
    ]);
    final compare = Block(equals.parameterTypes);
    compare.finish(
      Return(
        compare.emit(Equals(compare.parameters[0], compare.parameters[1])),
      ),
    );
    final output = FunctionTarget(_uri, 'output', .voidType, [.string]);
    final root = FunctionTarget(_uri, 'main', .integer, []);
    final entry = Block(), yes = Block(), no = Block();
    final call = entry.emit(
      DirectCall(equals, [
        const Constant.integer(1),
        const Constant.integer(2),
      ]),
    );
    entry.finish(Branch(call, Jump(yes), Jump(no)));
    yes.emit(DirectCall(output, [const Constant.string('unreachable')]));
    yes.finish(const Return(Constant.integer(-1)));
    no.finish(const Return(Constant.integer(7)));
    final program = IrProgram(
      [],
      [
        IrFunction(equals, [compare]),
        IrFunction(root, [entry, yes, no]),
      ],
      externals: [IrExternal(output)],
    );
    final entries = [(target: root, arguments: <FlowValue>[])];
    final before = ProgramFlow(program, entries).facts;
    expect(before.definitions, {root, equals});
    final optimizer = ProgramOptimizer([const ProgramSimplification()]);
    final after = optimizer.run(program, entries);
    expect(after.definitions, {root});
    expect(() => before.checkProgram(after.program), throwsArgumentError);
    for (final input in [program, after.program]) {
      expect(
        IrInterpreter(
          input,
          {},
        ).run(input.implementationOf(root) as IrFunction, []),
        7,
      );
    }
    expect(optimizer.run(after.program, entries).program, same(after.program));
  });

  test('known returns preserve side effects and exceptions', () {
    final output = FunctionTarget(_uri, 'output', .voidType, [.integer]);
    final helper = FunctionTarget(_uri, 'helper', .integer, [.integer]);
    final helperEntry = Block(helper.parameterTypes);
    helperEntry.emit(DirectCall(output, helperEntry.parameters));
    helperEntry.finish(const Return(Constant.integer(7)));
    final root = FunctionTarget(_uri, 'main', .integer, [.integer]);
    final entry = Block(root.parameterTypes),
        normal = Block([ValueType.integer]),
        caught = Block();
    final call = DirectCall(helper, entry.parameters);
    entry.finish(
      Invoke(call, onReturn: Jump(normal, [call]), onThrow: Jump(caught)),
    );
    normal.finish(Return(normal.parameters.single));
    caught.finish(const Return(Constant.integer(-1)));
    final program = IrProgram(
      [],
      [
        IrFunction(helper, [helperEntry]),
        IrFunction(root, [entry, normal, caught]),
      ],
      externals: [IrExternal(output)],
    );
    final facts = ProgramOptimizer([const ProgramSimplification()])
        .run(program, [], openEntries: [root]);
    for (final input in [program, facts.program]) {
      final events = <int>[];
      final interpreter = IrInterpreter(input, {
        (_uri, 'output'): (int value) {
          events.add(value);
          if (value < 0) throw StateError('failed');
          return null;
        },
      });
      final body = input.implementationOf(root) as IrFunction;
      expect(interpreter.run(body, [3]), 7);
      expect(interpreter.run(body, [-3]), -1);
      expect(events, [3, -3]);
    }
    expect(facts.definitions, {root, helper, output});
    expect(
      (facts.program.implementationOf(root) as IrFunction).entry.end,
      isA<Invoke>(),
    );
  });

  test('a possible return does not prove an unused call terminates', () {
    final wait = FunctionTarget(_uri, 'wait', .voidType, [.boolean]);
    final begin = Block(wait.parameterTypes), loop = Block(), done = Block();
    begin.finish(Branch(begin.parameters.single, Jump(done), Jump(loop)));
    loop.finish(Jump(loop));
    done.finish(const Return());
    final root = FunctionTarget(_uri, 'main', .integer, [.boolean]);
    final entry = Block(root.parameterTypes);
    entry.emit(DirectCall(wait, entry.parameters));
    entry.finish(const Return(Constant.integer(7)));
    final program = IrProgram([], [
      IrFunction(wait, [begin, loop, done]),
      IrFunction(root, [entry]),
    ]);
    final facts = ProgramOptimizer([const ProgramSimplification()])
        .run(program, [
          (target: root, arguments: [FlowValue.unknown(.boolean)]),
        ]);
    final body = facts.program.implementationOf(root) as IrFunction;
    expect(body.callees, contains(wait));
    expect(IrInterpreter(facts.program, {}).run(body, [true]), 7);
  });

  test(
    'proved non-returning calls drop their normal tails and retain handlers',
    () {
      final failure = FunctionTarget(_uri, 'failure', .integer, []);
      final throwing = Block()..finish(Throw(const Constant.integer(23)));
      final output = FunctionTarget(_uri, 'output', .voidType, [.integer]);
      final root = FunctionTarget(_uri, 'main', .integer, []);
      final entry = Block(), normal = Block(), caught = Block();
      final call = DirectCall(failure, []);
      entry.finish(Invoke(call, onReturn: Jump(normal), onThrow: Jump(caught)));
      normal.emit(DirectCall(output, [const Constant.integer(1)]));
      normal.finish(const Return(Constant.integer(-1)));
      caught.finish(const Return(Constant.integer(42)));
      final program = IrProgram(
        [],
        [
          IrFunction(failure, [throwing]),
          IrFunction(root, [entry, normal, caught]),
        ],
        externals: [IrExternal(output)],
      );
      final facts = ProgramOptimizer([const ProgramSimplification()])
          .run(program, [(target: root, arguments: <FlowValue>[])]);
      final body = facts.program.implementationOf(root) as IrFunction;
      expect(body.blocks, hasLength(2));
      expect((body.entry.end as Invoke).onReturn, isNull);
      expect(facts.definitions, {root, failure});
      expect(IrInterpreter(facts.program, {}).run(body, []), 42);

      final uncaught = Block();
      uncaught.emit(DirectCall(failure, []));
      uncaught.emit(DirectCall(output, [const Constant.integer(2)]));
      uncaught.finish(const Return(Constant.integer(-1)));
      final raw = IrProgram(
        [],
        [
          IrFunction(failure, [throwing]),
          IrFunction(root, [uncaught]),
        ],
        externals: [IrExternal(output)],
      );
      final result = ProgramOptimizer([const ProgramSimplification()])
          .run(raw, [(target: root, arguments: <FlowValue>[])]);
      final rewritten = result.program.implementationOf(root) as IrFunction;
      expect(rewritten.entry.instructions, hasLength(1));
      expect(rewritten.entry.end, isA<Unreachable>());
      expect(
        () => IrInterpreter(result.program, {}).run(rewritten, []),
        throwsA(23),
      );
    },
  );

  test('constant widening reaches a stable verified representation', () {
    final helper = FunctionTarget(_uri, 'boxed', .object, []);
    final value = Block();
    value.finish(
      Return(value.emit(TypeView(const Constant.integer(42), .object))),
    );
    final root = FunctionTarget(_uri, 'main', .object, []);
    final entry = Block();
    entry.finish(Return(entry.emit(DirectCall(helper, []))));
    final program = IrProgram([], [
      IrFunction(helper, [value]),
      IrFunction(root, [entry]),
    ]);
    final entries = [(target: root, arguments: <FlowValue>[])];
    final optimizer = ProgramOptimizer([const ProgramSimplification()]);
    final result = optimizer.run(program, entries);
    expect(
      IrInterpreter(
        result.program,
        {},
      ).run(result.program.implementationOf(root) as IrFunction, []),
      42,
    );
    expect(
      optimizer.run(result.program, entries).program,
      same(result.program),
    );
  });
}

final class _Layout(
  final IrProgram program, {
  Target target = const Target(.linux, .arm64),
}) implements FlowMemoryLayout {
  @override
  final nativeLayout = NativeLayout(target);

  @override
  ObjectLayout objectLayout(ClassType type) => ObjectLayout([
    for (final _ in program.classes.single.fields) ValueRepresentation.word,
  ]);
}

final class _AddField() extends ProgramPass {
  @override
  IrProgram run(ProgramFlowFacts facts) {
    final program = facts.program;
    final type = program.classes.single.type;
    if (program.classes.single.fields.isNotEmpty) return program;
    return IrProgram([
      IrClass(type, [InstanceField(type, 'prefix', .integer)]),
    ], program.functions);
  }
}

final class _Phase(
  @override final ProgramPassKind kind,
  final ProgramTransform Function() binding,
) extends ProgramPass {
  @override
  ProgramTransform bind() => binding();

  @override
  IrProgram run(ProgramFlowFacts facts) => bind()(facts);
}
