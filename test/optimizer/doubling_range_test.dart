import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

final uri = Uri.parse('memory:doubling');

IrFunction loop({
  int seed = 64,
  int factor = 2,
  IntOperator comparison = .lessThan,
  FunctionTarget? tick,
}) {
  final target = FunctionTarget(uri, 'loop', .integer, [.integer]);
  final entry = Block(target.parameterTypes),
      head = Block([ValueType.integer]),
      body = Block(),
      exit = Block();
  entry.finish(Jump(head, [Constant.integer(seed)]));
  final current = head.parameters.single;
  head.finish(
    Branch(
      head.emit(IntBinary(comparison, current, entry.parameters.single)),
      Jump(body),
      Jump(exit),
    ),
  );
  if (tick != null) body.emit(DirectCall(tick, [current]));
  body.finish(
    Jump(head, [
      body.emit(IntBinary(.multiply, current, Constant.integer(factor))),
    ]),
  );
  exit.finish(Return(current));
  return IrFunction(target, [entry, head, body, exit]);
}

void main() {
  test(
    'doubling to a threshold keeps singleton and bounded dynamic results',
    () {
      final function = loop(), program = IrProgram([], [function]);
      for (final (low, high, first, last) in [
        (48, 48, 64, 64),
        (96, 96, 128, 128),
        (65, 128, 128, 128),
        (48, 96, 64, 128),
      ]) {
        final range = ProgramFlow(program, [
          (
            target: function.target,
            arguments: [FlowValue.integerRange(FlowIntegerRange(low, high))],
          ),
        ]).facts.returnedBy(function.target).integers!;
        expect(
          [range.lower, range.upper],
          [first, last],
          reason: 'threshold [$low,$high]',
        );
        for (var input = low; input <= high; input++) {
          final result =
              IrInterpreter(program, {}).run(function, [input]) as int;
          expect(range.contains(result), isTrue);
        }
      }
    },
  );

  test(
    'descending loop inputs keep the first interval and widen further growth',
    () {
      final function = loop(seed: -64, comparison: .greaterThan);
      final graph = IrProgram([], [function]);
      final runner = IrInterpreter(graph, {});
      for (final threshold in [-48, -96, -257, -1025]) {
        final facts = ProgramFlow(graph, [
          (
            target: function.target,
            arguments: [FlowValue.constant(Constant.integer(threshold))],
          ),
        ]).facts;
        final range = facts.returnedBy(function.target).integers!;
        final actual = runner.run(function, [threshold]) as int;
        expect(range.contains(actual), isTrue);
        if (threshold >= -128) expect(range.constant, actual);
      }
    },
  );

  test('uncertain thresholds preserve the returning values and effects', () {
    final tick = FunctionTarget(uri, 'tick', .integer, [.integer]);
    final function = loop(tick: tick),
        program = IrProgram([], [function], externals: [IrExternal(tick)]);
    final facts =
        ProgramOptimizer(const [
          ProgramSimplification(),
          ProgramLoopSpecialization(),
        ]).run(program, [
          (target: function.target, arguments: [FlowValue.unknown(.integer)]),
        ]);
    final rewritten =
        facts.program.implementationOf(function.target) as IrFunction;
    final events = <int>[];
    final runner = IrInterpreter(
      facts.program,
      {},
      externalCalls: {
        tick: (args) {
          final value = args.single as int;
          events.add(value);
          return value;
        },
      },
    );
    expect(runner.run(rewritten, [48]), 64);
    expect(events, isEmpty);
    expect(runner.run(rewritten, [320]), 512);
    expect(events, [64, 128, 256]);
    for (final limit in [0, -48, 96, 257, 1 << 60, 1 << 62]) {
      final result = runner.run(rewritten, [limit]) as int;
      expect(
        facts.returnedBy(function.target).integers!.contains(result),
        isTrue,
        reason: 'threshold $limit',
      );
    }
    final throwing = IrInterpreter(
      facts.program,
      {},
      externalCalls: {tick: (_) => throw StateError('tick')},
    );
    expect(() => throwing.run(rewritten, [96]), throwsStateError);
  });

  test('wrapping cannot prove that a growing loop exits', () {
    final tick = FunctionTarget(uri, 'tick', .integer, [.integer]);
    final function = loop(seed: 1 << 62, tick: tick);
    final graph = IrProgram([], [function], externals: [IrExternal(tick)]);
    final facts =
        ProgramOptimizer(const [
          ProgramSimplification(),
          ProgramLoopSpecialization(),
        ]).run(graph, [
          (target: function.target, arguments: [FlowValue.unknown(.integer)]),
        ]);
    final rewritten =
        facts.program.implementationOf(function.target) as IrFunction;
    // Observe an unbounded execution without waiting for it to terminate.
    final events = <int>[];
    final stop = StateError('seen five iterations');
    final runner = IrInterpreter(
      facts.program,
      {},
      externalCalls: {
        tick: (args) {
          events.add(args.single as int);
          if (events.length == 5) throw stop;
          return 0;
        },
      },
    );
    expect(runner.run(rewritten, [1 << 62]), 1 << 62);
    expect(events, isEmpty);
    expect(
      () => runner.run(rewritten, [FlowIntegerRange.maximum]),
      throwsA(same(stop)),
    );
    expect(events, [1 << 62, FlowIntegerRange.minimum, 0, 0, 0]);
    final pure = loop(seed: 1 << 62), pureGraph = IrProgram([], [pure]);
    final pureFacts = ProgramFlow(pureGraph, [
      (
        target: pure.target,
        arguments: [FlowValue.integerRange(FlowIntegerRange.full)],
      ),
    ]).facts;
    expect(const ProgramLoopSpecialization().run(pureFacts), same(pureGraph));
    expect(
      const ProgramSimplification()
          .run(pureFacts)
          .functions
          .single
          .blocks
          .length,
      greaterThan(1),
    );
  });
}
