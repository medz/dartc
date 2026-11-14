import 'package:dartc/ir.dart';
import 'package:dartc/src/codegen/checked_casts.dart';
import 'package:dartc/src/codegen/global_storage.dart';
import 'package:dartc/src/codegen/heap_plan.dart';
import 'package:dartc/src/codegen/member_calls.dart';
import 'package:dartc/src/codegen/numeric_operations.dart';
import 'package:dartc/src/codegen/program_layout.dart';
import 'package:dartc/src/codegen/program_selection.dart';
import 'package:dartc/src/codegen/stack_traces.dart';
import 'package:test/test.dart';

import '../support/runtime.dart';

void main() {
  setUpAll(prepareRuntime);
  test('proved branches preserve effects and exception edges', () {
    for (final negated in [false, true]) {
      final uri = Uri.parse('memory:selection');
      final live = FunctionTarget(uri, 'live', .voidType, []);
      final dead = FunctionTarget(uri, 'dead', .voidType, []);
      final handler = FunctionTarget(uri, 'handler', .voidType, []);
      final root = FunctionTarget(uri, 'root', .integer, []);
      final entry = Block(),
          yes = Block(),
          no = Block(),
          done = Block(),
          caught = Block();
      entry.emit(DirectCall(live, []));
      entry.finish(
        Branch(
          entry.emit(
            TypeTest(const Constant.integer(1), .integer, negated: negated),
          ),
          Jump(negated ? no : yes),
          Jump(negated ? yes : no),
        ),
      );
      yes.finish(
        Invoke(
          DirectCall(live, []),
          onReturn: Jump(done),
          onThrow: Jump(caught),
        ),
      );
      done.finish(const Return(Constant.integer(42)));
      caught.emit(DirectCall(handler, []));
      caught.finish(const Return(Constant.integer(99)));
      no.emit(DirectCall(dead, []));
      no.finish(const Return(Constant.integer(0)));
      final function = IrFunction(root, [entry, yes, no, done, caught]);
      final casts = CheckedCasts();
      final layout = ProgramLayout([]);
      final selection = ProgramSelection(
        layout,
        HeapPlan(),
        StackTraces(null),
        casts,
        MemberCalls(
          IrProgram(
            [],
            [function],
            externals: [
              IrExternal(live),
              IrExternal(dead),
              IrExternal(handler),
            ],
          ),
          {},
        ),
        NumericOperations(),
        GlobalStorage([]),
        layout.instances,
      );
      selection.include(function);
      final selected = selection.functions[root]!;
      expect(selected.invocations.values, [live, live, handler]);
      expect(selected.blocks, [entry, yes, done, caught]);
      expect((selected.ends[yes] as Invoke).onThrow.target, same(caught));
      expect(entry.end, isA<Branch>());
    }
  });

  test('heap support closes transitively generated call dependencies', () {
    final program = IrProgram([], []);
    final casts = CheckedCasts();
    final traces = StackTraces(heapRuntime);
    final arithmetic = NumericOperations();
    final layouts = ProgramLayout([...casts.classes, ...arithmetic.classes]);
    final heap = HeapPlan(runtime: heapRuntime);
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

    final selection = ProgramSelection(
      layouts,
      heap,
      traces,
      casts,
      MemberCalls(program, {}),
      arithmetic,
      GlobalStorage([]),
      layouts.instances,
    );
    selection.include(IrFunction(helper, [entry]));
    selection.include(IrFunction(division, [divide]));
    expect(selection.close(persistent: true), {
      heapRuntime.allocate,
      heapRuntime.isOutOfMemory,
      heapRuntime.release,
      heapRuntime.captureStackTrace,
      heapRuntime.recordError,
    });
    expect(
      () => layouts.storageOf(CoreTypes.integerDivisionByZeroException),
      returnsNormally,
    );
    final definitions = {
      ...selection.functions.keys,
      ...selection.primitives,
      heapRuntime.allocate,
      heapRuntime.isOutOfMemory,
      heapRuntime.release,
      heapRuntime.captureStackTrace,
      heapRuntime.recordError,
      if (selection.capture) traces.capture,
    };
    for (final body in selection.functions.values) {
      expect(
        body.invocations.values
            .where((t) => !definitions.contains(t))
            .map((t) => t.name),
        isEmpty,
        reason: body.target.name,
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
    final casts = CheckedCasts();
    final traces = StackTraces(heapRuntime);
    final layouts = ProgramLayout([...casts.classes, ...program.classes]);
    final heap = HeapPlan(runtime: heapRuntime);
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

    final selection = ProgramSelection(
      layouts,
      heap,
      traces,
      casts,
      MemberCalls(program, {}),
      NumericOperations(argumentError: init),
      GlobalStorage([]),
      layouts.instances,
    );
    selection.include(IrFunction(helper, [entry]));
    expect(selection.close(persistent: true), {
      constructor,
      heapRuntime.allocate,
      heapRuntime.isOutOfMemory,
      heapRuntime.release,
      heapRuntime.captureStackTrace,
      heapRuntime.recordError,
    });
  });
}
