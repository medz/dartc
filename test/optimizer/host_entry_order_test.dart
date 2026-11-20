import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

void main() {
  for (final reverse in [false, true]) {
    for (final exceptional in [false, true]) {
      test(
        'host creates heap then invokes consumer independent of declaration order: reverse=$reverse throw=$exceptional',
        () {
          final uri = Uri.parse('memory:foreign-order');
          final box = ClassType(uri, 'Box');
          final held = GlobalVariable(uri, 'held', box.nullable);
          final slot = GlobalVariable(uri, 'value', .integer, isLate: true);
          final make = FunctionTarget(uri, 'install', .voidType, []),
              visit = FunctionTarget(uri, 'measure', .voidType, []);
          final caller = FunctionTarget(uri, 'outside', .integer, []),
              host = FunctionTarget(uri, 'host', .voidType, []);
          final mb = Block();
          mb.emit(
            StoreGlobal(
              held,
              mb.emit(NewPayload(box, const Constant.integer(0))),
            ),
          );
          mb.finish(const Return());
          final test = Block(), cold = Block(), warm = Block();
          test.finish(
            Branch(
              test.emit(
                Equals(test.emit(LoadGlobal(held)), const Constant.nullValue()),
              ),
              Jump(cold),
              Jump(warm),
            ),
          );
          cold.finish(const Return());
          warm.emit(StoreGlobal(slot, const Constant.integer(91)));
          warm.finish(
            exceptional ? Throw(const Constant.integer(7)) : const Return(),
          );
          final c = Block();
          c.emit(StoreGlobal(held, const Constant.nullValue()));
          c.emit(StoreGlobal(slot, const Constant.integer(3)));
          c.emit(DirectCall(host, []));
          c.finish(Return(c.emit(LoadGlobal(slot))));
          final install = IrFunction(make, [mb]),
              use = IrFunction(visit, [test, cold, warm]),
              run = IrFunction(caller, [c]);
          final p = IrProgram(
            [IrClass(box, [])],
            [install, use, run],
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
          final facts = ProgramFlow(p, [
            (target: caller, arguments: []),
          ], openEntries: reverse ? [make, visit] : [visit, make]).facts;
          final result = facts.returnedBy(caller).integers!;
          late IrInterpreter machine;
          machine = IrInterpreter(
            p,
            {},
            externalCalls: {
              host: (_) {
                machine.run(install, []);
                try {
                  machine.run(use, []);
                } catch (_) {
                  if (!exceptional) rethrow;
                }
                return null;
              },
            },
          );
          final concrete = machine.run(run, []);
          expect(concrete, 91);
          expect(result.contains(91), isTrue);
        },
      );
    }
  }
}
