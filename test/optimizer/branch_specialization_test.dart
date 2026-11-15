import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

void main() {
  test('known incoming types retain unknown paths, effects and handlers', () {
    final uri = Uri.parse('memory:branch');
    final tick = FunctionTarget(uri, 'tick', .integer, [.integer]);
    final root = FunctionTarget(uri, 'root', .integer, [.boolean, .object]);
    final entry = Block(root.parameterTypes),
        header = Block([ValueType.object]);
    final yes = Block(),
        no = Block(),
        done = Block([ValueType.integer]),
        caught = Block();
    entry.finish(
      Branch(
        entry.parameters.first,
        Jump(header, [const Constant.integer(7)]),
        Jump(header, [entry.parameters.last]),
      ),
    );
    final test = header.emit(TypeTest(header.parameters.single, .integer));
    header.finish(Branch(test, Jump(yes), Jump(no)));
    final checked = yes.emit(UncheckedCast(header.parameters.single, .integer));
    final call = DirectCall(tick, [checked]);
    yes.finish(
      Invoke(call, onReturn: Jump(done, [call]), onThrow: Jump(caught)),
    );
    done.finish(Return(done.parameters.single));
    caught.finish(const Return(Constant.integer(-99)));
    no.finish(const Return(Constant.integer(-1)));
    final location = SourceLocation((uri: uri, line: 43, column: 5));
    final function = IrFunction(
      root,
      [entry, header, yes, no, done, caught],
      sourceLocations: {call: location},
    );
    final program = IrProgram([], [function], externals: [IrExternal(tick)]);
    final roots = [
      (
        target: root,
        arguments: root.parameterTypes.map(FlowValue.unknown).toList(),
      ),
    ];
    final original = ProgramFlow(program, roots).facts;
    expect(
      const ProgramBranchSpecialization(maxCodeGrowth: 0).run(original),
      same(program),
    );
    final after = ProgramOptimizer(const [
      ProgramSimplification(),
      ProgramBranchSpecialization(),
    ]).run(program, roots).program;
    final rewritten = after.implementationOf(root) as IrFunction;
    expect(rewritten, isNot(same(function)));
    for (final graph in [program, after]) {
      for (final known in [false, true]) {
        for (final input in [11, -2, 'text']) {
          final events = <Object?>[];
          final runner = IrInterpreter(
            graph,
            {},
            externalCalls: {
              tick: (arguments) {
                events.add(arguments.single);
                final value = arguments.single as int;
                if (value < 0) throw StateError('tick');
                return value + 1;
              },
            },
          );
          final result = runner.run(
            graph.implementationOf(root) as IrFunction,
            [known, input],
          );
          final actual = known ? 7 : input;
          expect(
            result,
            actual is! int
                ? -1
                : actual < 0
                ? -99
                : actual + 1,
          );
          expect(events, actual is int ? [actual] : isEmpty);
        }
      }
    }
    for (final block in rewritten.blocks) {
      if (block.end case Invoke(operation: final DirectCall operation)) {
        expect(rewritten.sourceLocations[operation], location);
      }
    }
  });
}
