import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

void main() {
  for (final withHeap in [false, true]) {
    for (final throws in [false, true]) {
      test(
        'an existing outside call admits a newly opened callback, heap=$withHeap throw=$throws',
        () {
          final uri = Uri.parse('memory:open-after-foreign-call');
          final box = ClassType(uri, 'Box');
          final held = GlobalVariable(uri, 'held', box.nullable);
          final slot = GlobalVariable(uri, 'slot', .integer, isLate: true);
          final setter = FunctionTarget(uri, 'write', .voidType, []),
              caller = FunctionTarget(uri, 'outside', .integer, []);
          final host = FunctionTarget(uri, 'host', .voidType, []);
          final set = Block();
          set.emit(StoreGlobal(slot, const Constant.integer(91)));
          set.finish(
            throws ? Throw(const Constant.integer(7)) : const Return(),
          );
          final entry = Block();
          entry.emit(StoreGlobal(slot, const Constant.integer(3)));
          if (withHeap) {
            entry.emit(
              StoreGlobal(
                held,
                entry.emit(NewPayload(box, const Constant.integer(0))),
              ),
            );
          }
          entry.emit(DirectCall(host, []));
          final observed = entry.emit(LoadGlobal(slot));
          entry.finish(Return(observed));
          final run = IrFunction(caller, [entry]),
              writer = IrFunction(setter, [set]);
          final program = IrProgram(
            [IrClass(box, [])],
            [run, writer],
            globals: [held, slot],
            externals: [
              IrExternal(
                host,
                effects: {Effect.callsUserCode},
                memory: const .unchanged(),
                capturesArguments: false,
              ),
            ],
          );
          final initial = [(target: caller, arguments: <FlowValue>[])];
          final flow = ProgramFlow(program, initial);
          final first = flow.facts.returnedBy(caller).integers!;
          expect(first.constant, 3);
          final fresh = ProgramFlow(
            program,
            initial,
            openEntries: [setter],
          ).facts.returnedBy(caller).integers!;
          expect(flow.extend(openEntries: [setter]), isTrue);
          final extended = flow.facts.returnedBy(caller).integers!;
          late IrInterpreter machine;
          machine = IrInterpreter(
            program,
            {},
            externalCalls: {
              host: (_) {
                try {
                  machine.run(writer, []);
                } catch (_) {
                  if (!throws) rethrow;
                }
                return null;
              },
            },
          );
          final concrete = machine.run(run, []);
          expect(concrete, 91);
          expect(fresh.contains(91), isTrue);
          expect(extended.contains(91), isTrue);
        },
      );
    }
  }
}
