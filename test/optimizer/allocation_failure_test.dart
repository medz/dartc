import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

void main() {
  final storage = ClassType(null, 'Storage');
  final failure = FunctionTarget(null, 'failure', .never, []);
  final reported = const Constant.string('resource exhausted');

  test('ordinary failure bodies supply actual values, effects and state', () {
    final global = GlobalVariable(
      Uri.parse('memory:allocation'),
      'saved',
      .integer,
      isLate: true,
    );
    final reporting = Block();
    reporting.emit(StoreGlobal(global, const Constant.integer(31)));
    reporting.finish(Throw(reported));
    final root = FunctionTarget(null, 'root', .integer, []);
    final observer = FunctionTarget(null, 'observe', .integer, [storage]);
    final entry = Block(), normal = Block([storage]), handler = Block();
    entry.emit(StoreGlobal(global, const Constant.integer(7)));
    final allocation = NewPayload(storage, const Constant.integer(0));
    entry.finish(
      Invoke(
        allocation,
        onReturn: Jump(normal, [allocation]),
        onThrow: Jump(handler),
      ),
    );
    normal.finish(Return(normal.emit(DirectCall(observer, normal.parameters))));
    final saved = handler.emit(LoadGlobal(global));
    handler.finish(Return(saved));
    final function = IrFunction(root, [entry, normal, handler]);
    final program = IrProgram(
      [IrClass(storage, [])],
      [
        function,
        IrFunction(failure, [reporting]),
      ],
      globals: [global],
      externals: [IrExternal(observer)],
    );
    final facts = ProgramFlow(program, [
      (target: root, arguments: []),
    ], allocationFailure: failure).facts;
    expect(facts.failureOf(allocation).exception.constant, reported);
    expect(facts.valueOf(saved).constant, const Constant.integer(31));
    expect(facts.effectsOf(allocation), contains(Effect.writesStorage));
    expect(facts.targetsOf(allocation), isEmpty);
    expect(facts.canDiscard(allocation), isFalse);
    final lowered = FunctionRewrite(
      function,
      operations: {allocation: DirectCall(failure, [])},
    ).run();
    final forced = IrProgram(
      program.classes,
      [
        lowered,
        IrFunction(failure, [reporting]),
      ],
      globals: program.globals,
      externals: program.externals,
    );
    expect(IrInterpreter(forced, {}).run(lowered, []), 31);
  });

  test(
    'unused allocations disappear without erasing an explicit failure call',
    () {
      final reporting = IrFunction(failure, [Block()..finish(Throw(reported))]);
      for (final explicit in [false, true]) {
        final root = FunctionTarget(null, 'root', .integer, []);
        final entry = Block();
        final Instruction operation = explicit
            ? DirectCall(failure, [])
            : NewPayload(storage, const Constant.integer(0));
        entry.emit(operation);
        entry.finish(
          explicit
              ? Unreachable(operation)
              : const Return(Constant.integer(42)),
        );
        final original = IrFunction(root, [entry]);
        final program = IrProgram(
          [IrClass(storage, [])],
          [original, reporting],
        );
        final roots = [(target: root, arguments: <FlowValue>[])];
        final before = ProgramFlow(
          program,
          roots,
          allocationFailure: failure,
        ).facts;
        expect(before.canDiscard(operation), !explicit);
        final after = ProgramOptimizer(const [ProgramSimplification()])
            .run(program, roots, allocationFailure: failure);
        final body = after.program.implementationOf(root) as IrFunction;
        final runner = IrInterpreter(after.program, {});
        if (explicit) {
          expect(() => runner.run(body, []), throwsA('resource exhausted'));
        } else {
          expect(runner.run(body, []), 42);
          expect(after.definitions, {root});
          expect(body.entry.instructions, isEmpty);
        }
      }
    },
  );

  test('allocation failure reporting rejects another allocation', () {
    final reporting = Block()..emit(CaptureStackTrace());
    reporting.finish(Throw(reported));
    final root = FunctionTarget(null, 'root', storage, []);
    final entry = Block();
    entry.finish(
      Return(entry.emit(NewPayload(storage, const Constant.integer(0)))),
    );
    final program = IrProgram(
      [IrClass(storage, [])],
      [
        IrFunction(root, [entry]),
        IrFunction(failure, [reporting]),
      ],
    );
    expect(
      () => ProgramFlow(program, [
        (target: root, arguments: []),
      ], allocationFailure: failure),
      throwsStateError,
    );
    expect(
      () => ProgramFlow(program, [
        (target: root, arguments: []),
      ], allocationFailure: root),
      throwsArgumentError,
    );
  });
}
