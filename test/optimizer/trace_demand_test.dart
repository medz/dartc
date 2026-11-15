import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

void main() {
  for (final observed in [false, true]) {
    for (final openThrower in [false, true]) {
      test(
        'rethrow demand crosses calls (observed=$observed, open=$openThrower)',
        () {
          final raise = FunctionTarget(null, 'raise', .never, [.integer]);
          final raised = Block(raise.parameterTypes);
          final trace = raised.emit(CaptureStackTrace());
          raised.finish(Throw.recorded(raised.parameters.single, trace));
          final forward = FunctionTarget(null, 'forward', .never, [.integer]);
          final forwarding = Block(forward.parameterTypes);
          final rethrowing = Block([.object, .stackTrace]);
          forwarding.finish(
            Invoke(
              DirectCall(raise, forwarding.parameters),
              onReturn: null,
              onThrow: Jump(rethrowing, [
                UnwindValue.exception,
                UnwindValue.stackTrace,
              ]),
            ),
          );
          rethrowing.finish(
            Throw.recorded(
              rethrowing.parameters.first,
              rethrowing.parameters.last,
            ),
          );
          final root = FunctionTarget(
            null,
            'root',
            observed ? .stackTrace : .object,
            [.integer],
          );
          final entry = Block(root.parameterTypes);
          final handler = Block([.object, .stackTrace]);
          entry.finish(
            Invoke(
              DirectCall(forward, entry.parameters),
              onReturn: null,
              onThrow: Jump(handler, [
                UnwindValue.exception,
                UnwindValue.stackTrace,
              ]),
            ),
          );
          handler.finish(Return(handler.parameters[observed ? 1 : 0]));
          final program = IrProgram([], [
            IrFunction(root, [entry, handler]),
            IrFunction(forward, [forwarding, rethrowing]),
            IrFunction(raise, [raised]),
          ]);
          final facts = ProgramOptimizer(const [ProgramSimplification()])
              .run(program, [], openEntries: [root, if (openThrower) raise]);
          final body = facts.program.implementationOf(raise) as IrFunction;
          expect(
            body.entry.instructions.whereType<CaptureStackTrace>(),
            observed || openThrower ? hasLength(1) : isEmpty,
          );
          expect(
            (body.entry.end as Throw).stackTrace != null,
            observed || openThrower,
          );
          final caller = facts.program.implementationOf(root) as IrFunction;
          for (final value in [-7, 0, 42]) {
            final actual = IrInterpreter(
              facts.program,
              {},
            ).run(caller, [value]);
            if (observed) {
              expect(actual, isA<StackTrace>());
              expect(actual.toString(), isNotEmpty);
            } else {
              expect(actual, value);
            }
          }
        },
      );
    }
  }

  test('recording a trace remains observable when the handler ignores it', () {
    final record = FunctionTarget(null, 'record', .voidType, [.stackTrace]);
    final raise = FunctionTarget(null, 'raise', .never, []);
    final raised = Block();
    final trace = raised.emit(CaptureStackTrace());
    raised.emit(DirectCall(record, [trace]));
    raised.finish(Throw.recorded(const Constant.integer(7), trace));
    final root = FunctionTarget(null, 'root', .integer, []);
    final entry = Block(),
        handler = Block()..finish(const Return(Constant.integer(42)));
    entry.finish(
      Invoke(DirectCall(raise, []), onReturn: null, onThrow: Jump(handler)),
    );
    final program = IrProgram(
      [],
      [
        IrFunction(raise, [raised]),
        IrFunction(root, [entry, handler]),
      ],
      externals: [
        IrExternal(record, effects: const {.writesStorage}, terminates: true),
      ],
    );
    final facts = ProgramOptimizer(const [ProgramSimplification()])
        .run(program, [(target: root, arguments: [])]);
    final body = facts.program.implementationOf(raise) as IrFunction;
    expect((body.entry.end as Throw).stackTrace, isNull);
    final recorded = <Object?>[];
    final interpreter = IrInterpreter(
      facts.program,
      {},
      externalCalls: {
        record: (arguments) {
          recorded.add(arguments.single);
          return null;
        },
      },
    );
    expect(
      interpreter.run(facts.program.implementationOf(root) as IrFunction, []),
      42,
    );
    expect(recorded.single, isA<StackTrace>());
  });

  test(
    'a callback returned to an external caller keeps its exception trace',
    () {
      final raise = FunctionTarget(null, 'raise', .never, []);
      final raised = Block();
      raised.finish(
        Throw.recorded(
          const Constant.integer(7),
          raised.emit(CaptureStackTrace()),
        ),
      );
      final root = FunctionTarget(null, 'root', raise.signature, []);
      final entry = Block()..finish(Return(FunctionConstant(raise)));
      final program = IrProgram([], [
        IrFunction(raise, [raised]),
        IrFunction(root, [entry]),
      ]);
      final facts = ProgramOptimizer(const [ProgramSimplification()])
          .run(program, [], openEntries: [root]);
      final body = facts.program.implementationOf(raise) as IrFunction;
      expect((body.entry.end as Throw).stackTrace, isA<CaptureStackTrace>());
    },
  );
}
