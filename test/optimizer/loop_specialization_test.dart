import 'package:dartc/frontend.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';
import '../frontend/lowering/fixtures/effects.dart' as effects;
import 'fixtures/finite_loops.dart' as source;

void main() {
  test(
    'known loop computation disappears before a large runtime continuation',
    () {
      final target = FunctionTarget(
        Uri.parse('memory:loop-continuation'),
        'compute',
        .integer,
        [.integer],
      );
      final entry = Block(target.parameterTypes),
          header = Block([ValueType.integer, ValueType.integer]),
          step = Block(),
          done = Block();
      entry.finish(
        Jump(header, const [Constant.integer(0), Constant.integer(0)]),
      );
      final index = header.parameters.first, sum = header.parameters.last;
      header.finish(
        Branch(
          header.emit(IntBinary(.lessThan, index, const Constant.integer(4))),
          Jump(step),
          Jump(done),
        ),
      );
      final digit = step.emit(
        IntBinary(
          .add,
          step.emit(IntBinary(.multiply, sum, const Constant.integer(10))),
          index,
        ),
      );
      step.finish(
        Jump(header, [
          step.emit(IntBinary(.add, index, const Constant.integer(1))),
          digit,
        ]),
      );
      Value result = done.emit(IntBinary(.add, entry.parameters.single, sum));
      for (var value = 1; value <= 80; value++) {
        result = done.emit(IntBinary(.add, result, Constant.integer(value)));
      }
      done.finish(Return(result));
      final original = IrFunction(target, [entry, header, step, done]);
      final graph = IrProgram([], [original]);
      final facts =
          ProgramOptimizer(const [
            ProgramSimplification(),
            ProgramLoopSpecialization(),
          ]).run(graph, [
            (target: target, arguments: [FlowValue.unknown(.integer)]),
          ]);
      final rewritten = facts.program.implementationOf(target) as IrFunction;
      for (final input in [
        FlowIntegerRange.minimum,
        -5,
        0,
        17,
        FlowIntegerRange.maximum,
      ]) {
        expect(
          IrInterpreter(facts.program, {}).run(rewritten, [input]),
          input + 123 + 3240,
        );
        expect(
          IrInterpreter(graph, {}).run(original, [input]),
          input + 123 + 3240,
        );
      }
      expect(rewritten.blocks, hasLength(1));
      expect(rewritten.entry.instructions, hasLength(81));
    },
  );

  test(
    'new graph origins preserve source sites and reject foreign metadata',
    () {
      final uri = Uri.parse('memory:loop-source');
      final target = FunctionTarget(uri, 'entry', .integer, []);
      final entry = Block();
      final original = entry.emit(
        IntBinary(.add, const Constant.integer(1), const Constant.integer(2)),
      );
      entry.finish(Return(original));
      final location = SourceLocation((uri: uri, line: 7, column: 3));
      final function = IrFunction(
        target,
        [entry],
        sourceLocations: {original: location},
      );
      final next = Block();
      final copied = next.emit(
        IntBinary(.add, const Constant.integer(3), const Constant.integer(4)),
      );
      next.finish(Return(copied));
      final rewritten = FunctionRewrite(
        function,
        terminators: {entry: Jump(next)},
        origins: {copied: original},
      ).run();
      expect(
        IrInterpreter(IrProgram([], [rewritten]), {}).run(rewritten, []),
        7,
      );
      final operation = rewritten.blocks
          .expand((block) => block.instructions)
          .whereType<IntBinary>()
          .single;
      expect(rewritten.sourceLocations[operation], same(location));
      for (final origins in [
        {copied: Block()},
        {Block(): original},
        {original: original},
      ]) {
        expect(
          () => FunctionRewrite(
            function,
            terminators: {entry: Jump(next)},
            origins: origins,
          ).run(),
          throwsArgumentError,
        );
      }
    },
  );

  late IrProgram program;
  IrFunction body(String name) => program.functions.singleWhere(
    (body) => body.target.name == name && body.target.owner == null,
  );
  setUpAll(() async {
    program = await AnalysisSession([
      'test/optimizer/fixtures/finite_loops.dart',
    ]).use((input) async => (await Lowering().lower(input)).program);
    final tick = program.functions
        .expand((body) => body.callees)
        .where((target) => target.name == 'tick')
        .first;
    program = IrProgram(
      program.classes,
      program.functions,
      globals: program.globals,
      externals: [...program.externals, IrExternal(tick)],
    );
  });
  ProgramFlowFacts optimize(IrFunction function) =>
      ProgramOptimizer(const [
        ProgramSimplification(),
        ProgramCallSpecialization(),
        ProgramStoragePromotion(),
        ProgramStorageElimination(),
        ProgramLoopSpecialization(),
        DirectCallInlining(),
      ]).run(program, [
        (
          target: function.target,
          arguments: function.target.parameterTypes
              .map(FlowValue.unknown)
              .toList(),
        ),
      ]);

  for (final name in [
    'unusedIncreasing',
    'unusedDecreasing',
    'unusedNested',
    'unusedBreaking',
  ]) {
    test('$name removes finite unused work for runtime bounds', () {
      final function = body(name), facts = optimize(body(name));
      final result =
          facts.program.implementationOf(function.target) as IrFunction;
      expect(result.blocks, hasLength(1));
      expect(result.entry.instructions, isEmpty);
      for (final bound in [
        FlowIntegerRange.minimum,
        -5,
        0,
        5,
        FlowIntegerRange.maximum,
      ]) {
        expect(IrInterpreter(facts.program, {}).run(result, [bound]), bound);
      }
    });
  }

  for (final name in ['unusedWrapping', 'stalledInner']) {
    test('$name preserves possible nontermination', () {
      final function = body(name), facts = optimize(body(name));
      final result =
          facts.program.implementationOf(function.target) as IrFunction;
      expect(result.blocks.length, greaterThan(1));
      expect(IrInterpreter(facts.program, {}).run(result, [-1]), -1);
    });
  }

  test('a growing capacity exits at the first power above the threshold', () {
    final function = body('roundCapacity');
    final facts = ProgramFlow(program, [
      (
        target: function.target,
        arguments: [FlowValue.constant(const Constant.integer(168))],
      ),
    ]).facts;
    expect(facts.returnedBy(function.target).integers?.constant, 256);
    expect(source.roundCapacity(168), 256);
  });

  test('loop elimination preserves exit values and arithmetic failures', () {
    final function = body('runtimeExitValue'),
        facts = optimize(body('runtimeExitValue'));
    final result =
        facts.program.implementationOf(function.target) as IrFunction;
    for (final bound in [-5, 0, 1, 8]) {
      expect(
        IrInterpreter(facts.program, {}).run(result, [bound]),
        source.runtimeExitValue(bound),
      );
    }
    final checked = body('retainedCheck'),
        checkedFacts = optimize(body('retainedCheck'));
    final checkedResult =
        checkedFacts.program.implementationOf(checked.target) as IrFunction;
    final interpreter = IrInterpreter(checkedFacts.program, {});
    expect(interpreter.run(checkedResult, [0, 0]), 0);
    expect(interpreter.run(checkedResult, [3, 2]), 3);
    expect(
      () => interpreter.run(checkedResult, [3, 0]),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('nested loop re-entry invalidates previous bounds', () {
    final function = body('nestedRuntime'),
        facts = optimize(body('nestedRuntime'));
    final result =
        facts.program.implementationOf(function.target) as IrFunction;
    for (final bound in [-2, 0, 1, 4, 9]) {
      expect(
        IrInterpreter(facts.program, {}).run(result, [bound]),
        source.nestedRuntime(bound),
      );
    }
  });

  for (final (name, evaluate) in <(String, int Function())>[
    ('digits', source.digits),
    ('countdown', source.countdown),
    ('stepped', source.stepped),
    ('descending', source.descending),
    ('reversed', source.reversed),
    ('once', source.once),
    ('nested', source.nested),
    ('objects', source.objects),
    ('nearLimit', source.nearLimit),
    ('lowerLimit', source.lowerLimit),
  ]) {
    test('source $name leaves only its known accumulated result', () {
      final function = body(name), expected = evaluate();
      final facts = optimize(function);
      final result =
          facts.program.implementationOf(function.target) as IrFunction;
      expect(IrInterpreter(facts.program, {}).run(result, []), expected);
      expect(
        facts.returnedBy(function.target).constant?.structuralKey,
        Constant.integer(expected).structuralKey,
      );
      expect(facts.definitions, {function.target});
      expect(result.blocks, hasLength(1));
      expect(result.entry.instructions, isEmpty);
    });
  }

  test('runtime loop counts and wraparound do not establish a finite constant counter', () {
    for (final name in ['runtimeCount', 'wrapping', 'missingStop']) {
      final function = body(name);
      final facts = ProgramFlow(program, [
        (
          target: function.target,
          arguments: function.target.parameterTypes
              .map(FlowValue.unknown)
              .toList(),
        ),
      ]).facts;
      expect(const ProgramLoopSpecialization().run(facts), same(program));
    }
    final function = body('runtimeCount'),
        facts = optimize(body('runtimeCount'));
    for (final count in [-1, 0, 1, 4, 8]) {
      expect(
        IrInterpreter(facts.program, {}).run(
          facts.program.implementationOf(function.target) as IrFunction,
          [count],
        ),
        source.runtimeCount(count),
      );
    }
  });

  test('a changing exit bound is not frozen at its initial value', () {
    final function = body('changingLimit'),
        facts = optimize(body('changingLimit'));
    expect(
      IrInterpreter(
        facts.program,
        {},
      ).run(facts.program.implementationOf(function.target) as IrFunction, []),
      source.changingLimit(),
    );
    expect(facts.returnedBy(function.target).integers!.contains(7), isTrue);
  });

  test('peeling preserves break, catch, finally and observable call order', () {
    final function = body('earlyExit'), facts = optimize(body('earlyExit'));
    final runner = IrInterpreter(facts.program, {
      (
        Uri.base.resolve('test/frontend/lowering/fixtures/effects.dart'),
        'tick',
      ): effects.tick,
    });
    for (final stop in [-5, -3, -1, 0, 1, 3, 5]) {
      effects.calls.clear();
      final expected = source.earlyExit(stop), calls = List.of(effects.calls);
      effects.calls.clear();
      final actual = runner.run(
        facts.program.implementationOf(function.target) as IrFunction,
        [stop],
      );
      expect(actual, expected, reason: 'stop=$stop');
      expect(effects.calls, calls, reason: 'stop=$stop');
    }
    final originalCalls = function.blocks
        .expand((block) => block.instructions)
        .whereType<DirectCall>()
        .where((call) => call.target.name == 'tick');
    final locations = originalCalls
        .map((call) => function.sourceLocations[call])
        .toSet();
    expect(locations, isNot(contains(null)));
    for (final rewritten in facts.program.functions.where(
      (body) => facts.definitions.contains(body.target),
    )) {
      for (final operation
          in rewritten.blocks
              .expand(
                (block) => [
                  ...block.instructions,
                  if (block.end case Invoke(:final operation)) operation,
                ],
              )
              .whereType<DirectCall>()
              .where((call) => call.target.name == 'tick')) {
        expect(rewritten.sourceLocations[operation], isIn(locations));
      }
    }
  });

  for (final (name, evaluate) in <(String, int Function(int))>[
    ('continued', source.continued),
    ('outerCatch', source.outerCatch),
    ('continuationLoop', source.continuationLoop),
  ]) {
    test('source $name retains its runtime edge values after peeling', () {
      final function = body(name), facts = optimize(body(name));
      final rewritten =
          facts.program.implementationOf(function.target) as IrFunction;
      for (final value in [
        FlowIntegerRange.minimum,
        -1,
        0,
        1,
        3,
        5,
        FlowIntegerRange.maximum,
      ]) {
        expect(
          IrInterpreter(facts.program, {}).run(rewritten, [value]),
          evaluate(value),
        );
      }
      if (name == 'continuationLoop') {
        expect(
          rewritten.blocks.where((block) => block.end is Branch),
          hasLength(1),
        );
      }
    });
  }

  test(
    'one compilation retains its expansion budget for a large finite loop',
    () {
      final function = body('runtimeCount');
      final entry = (
        target: function.target,
        arguments: [FlowValue.constant(const Constant.integer(1000000))],
      );
      final expand = const ProgramLoopSpecialization(maxCodeGrowth: 12).bind();
      final first = expand(ProgramFlow(program, [entry]).facts);
      expect(first, isNot(same(program)));
      final next = expand(ProgramFlow(first, [entry]).facts);
      expect(next, same(first));
    },
  );
}
