import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

void main() {
  test('recomputed arithmetic retains the dominating bounds check', () {
    final target = FunctionTarget(null, 'checked', .integer, [.integer]);
    final use = FunctionTarget(null, 'use', .integer, [.integer]);
    final callee = Block(use.parameterTypes);
    callee.finish(Return(callee.parameters.single));
    final entry = Block(target.parameterTypes),
        upper = Block(),
        success = Block(),
        failed = Block()..finish(const Return(Constant.integer(-1)));
    final index = entry.parameters.single;
    final checked = entry.emit(
      IntBinary(.add, index, const Constant.integer(1)),
    );
    entry.finish(
      Branch(
        entry.emit(IntBinary(.lessThan, checked, const Constant.integer(0))),
        Jump(failed),
        Jump(upper),
      ),
    );
    upper.finish(
      Branch(
        upper.emit(IntBinary(.lessThan, checked, const Constant.integer(12))),
        Jump(success),
        Jump(failed),
      ),
    );
    final repeated = success.emit(
      IntBinary(.add, index, const Constant.integer(1)),
    );
    success.finish(Return(success.emit(DirectCall(use, [repeated]))));
    final original = IrFunction(target, [entry, upper, success, failed]);
    final program = IrProgram([], [
      original,
      IrFunction(use, [callee]),
    ]);
    final facts = ProgramFlow(
      const ProgramSimplification().bind().normalize(program),
      [
        (target: target, arguments: [FlowValue.unknown(.integer)]),
      ],
    ).facts;
    final range = facts.returnedBy(use).integers!;
    expect((range.lower, range.upper), (0, 11));
    final rewritten = facts.program.implementationOf(target) as IrFunction;
    for (final input in [
      FlowIntegerRange.minimum,
      -3,
      -1,
      0,
      10,
      11,
      FlowIntegerRange.maximum,
    ]) {
      expect(
        IrInterpreter(facts.program, {}).run(rewritten, [input]),
        IrInterpreter(program, {}).run(original, [input]),
      );
    }
  });

  test('equal sibling expressions do not create a cross-branch use', () {
    final target = FunctionTarget(null, 'choose', .integer, [
      .boolean,
      .integer,
    ]);
    final entry = Block(target.parameterTypes), yes = Block(), no = Block();
    entry.finish(Branch(entry.parameters.first, Jump(yes), Jump(no)));
    for (final block in [yes, no]) {
      block.finish(
        Return(
          block.emit(
            IntBinary(.add, entry.parameters.last, const Constant.integer(1)),
          ),
        ),
      );
    }
    final program = IrProgram([], [
      IrFunction(target, [entry, yes, no]),
    ]);
    final facts = ProgramOptimizer(const [ProgramSimplification()]).run(
      program,
      [
        (
          target: target,
          arguments: [FlowValue.unknown(.boolean), FlowValue.unknown(.integer)],
        ),
      ],
    );
    final rewritten = facts.program.implementationOf(target) as IrFunction;
    for (final flag in [true, false]) {
      expect(IrInterpreter(facts.program, {}).run(rewritten, [flag, 41]), 42);
    }
  });
}
