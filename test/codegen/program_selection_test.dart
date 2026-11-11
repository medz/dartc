import 'package:dartc/ir.dart';
import 'package:dartc/src/codegen/checked_casts.dart';
import 'package:dartc/src/codegen/frame_lookup.dart';
import 'package:dartc/src/codegen/global_storage.dart';
import 'package:dartc/src/codegen/heap_plan.dart';
import 'package:dartc/src/codegen/member_calls.dart';
import 'package:dartc/src/codegen/numeric_operations.dart';
import 'package:dartc/src/codegen/program_layout.dart';
import 'package:dartc/src/codegen/program_selection.dart';
import 'package:dartc/src/codegen/stack_traces.dart';
import 'package:test/test.dart';

void main() {
  test('heap support closes transitively generated call dependencies', () {
    final program = IrProgram([], []);
    final frames = FrameLookup(), casts = CheckedCasts();
    final traces = StackTraces(frames);
    final arithmetic = NumericOperations();
    final layouts = ProgramLayout([
      ...casts.classes,
      ...arithmetic.classes,
      traces.declaration,
    ]);
    final heap = HeapPlan(frames);
    final helper = FunctionTarget(
      Uri.parse('memory:heap-support'),
      'round',
      .floating,
      [.floating],
    );
    final entry = Block(helper.parameterTypes);
    entry.finish(
      Return(entry.emit(NumericRoundToDouble(entry.parameters.single, .round))),
    );
    heap.functions.add(IrFunction(helper, [entry]));
    final division = FunctionTarget(helper.library, 'divide', .integer, [
      .integer,
      .integer,
    ]);
    final divide = Block(division.parameterTypes);
    divide.finish(
      Return(
        divide.emit(
          IntBinary(
            .truncateDivide,
            divide.parameters[0],
            divide.parameters[1],
          ),
        ),
      ),
    );
    heap.functions.add(IrFunction(division, [divide]));
    final selection = ProgramSelection(
      layouts,
      heap,
      frames,
      traces,
      casts,
      MemberCalls(program, {}),
      arithmetic,
      GlobalStorage([]),
      layouts.instances,
    );
    expect(selection.close(persistent: true), isEmpty);
    expect(arithmetic.functions.length, greaterThanOrEqualTo(2));
    expect(
      () => layouts.storageOf(CoreTypes.integerDivisionByZeroException),
      returnsNormally,
    );
    final definitions = {
      ...selection.functions.keys,
      ...selection.primitives,
      if (selection.capture) traces.capture,
    };
    for (final body in selection.functions.values) {
      expect(
        body.invocations.values
            .where((t) => !definitions.contains(t))
            .map((t) => t.name),
        isEmpty,
        reason: body.function.target.name,
      );
    }
  });

  test('allocation wrappers report source constructor dependencies', () {
    final constructor = FunctionTarget(
      Uri.parse('dart:core'),
      'new',
      .voidType,
      [.integer],
      owner: ValueType.argumentError,
      kind: .initializer,
    );
    final init = IrFunction(constructor, [
      Block(constructor.parameterTypes)..finish(const Return()),
    ]);
    final program = IrProgram(
      [
        IrClass(ValueType.argumentError, [], constructors: [constructor]),
      ],
      [init],
    );
    final frames = FrameLookup(), casts = CheckedCasts();
    final traces = StackTraces(frames);
    final layouts = ProgramLayout([
      ...casts.classes,
      ...program.classes,
      traces.declaration,
    ]);
    final heap = HeapPlan(frames);
    final helper = FunctionTarget(
      Uri.parse('memory:heap-support'),
      'shift',
      .integer,
      [.integer, .integer],
    );
    final entry = Block(helper.parameterTypes);
    entry.finish(
      Return(
        entry.emit(
          IntBinary(
            .unsignedShiftRight,
            entry.parameters[0],
            entry.parameters[1],
          ),
        ),
      ),
    );
    heap.functions.add(IrFunction(helper, [entry]));
    final selection = ProgramSelection(
      layouts,
      heap,
      frames,
      traces,
      casts,
      MemberCalls(program, {}),
      NumericOperations(argumentError: init),
      GlobalStorage([]),
      layouts.instances,
    );
    expect(selection.close(persistent: true), {constructor});
  });
}
