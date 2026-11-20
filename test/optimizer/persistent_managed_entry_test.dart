import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

void main() {
  test('a fresh return cannot overwrite the first live object', () {
    final uri = Uri.parse('memory:managed-lifetimes');
    final box = ClassType(uri, 'Box');
    final value = InstanceField(box, 'value', .integer);
    final first = GlobalVariable(uri, 'first', box.nullable);
    final create = FunctionTarget(uri, 'create', box, []);
    final make = Block();
    final fresh = make.emit(NewPayload(box, const Constant.integer(0)));
    make.emit(StoreField(value, fresh, const Constant.integer(37)));
    make.finish(Return(fresh));

    final root = FunctionTarget(uri, 'visit', .integer, []);
    final call = Block(), save = Block(), later = Block();
    final prior = call.emit(LoadGlobal(first));
    final next = call.emit(DirectCall(create, []));
    call.finish(
      Branch(
        call.emit(Equals(prior, const Constant.nullValue())),
        Jump(save),
        Jump(later),
      ),
    );
    save.emit(StoreGlobal(first, next));
    save.finish(const Return(Constant.integer(0)));
    later.emit(StoreField(value, next, const Constant.integer(91)));
    final read = later.emit(LoadField(value, later.emit(NullCheck(prior))));
    later.finish(Return(read));
    final entry = IrFunction(root, [call, save, later]);
    final program = IrProgram(
      [
        IrClass(box, [value]),
      ],
      [
        IrFunction(create, [make]),
        entry,
      ],
      globals: [first],
    );
    final interpreter = IrInterpreter(program, {});
    expect(List.generate(4, (_) => interpreter.run(entry, [])), [
      0,
      37,
      37,
      37,
    ]);
    final facts = ProgramFlow(program, const [], openEntries: [root]).facts;
    final range = facts.valueOf(read).integers;
    expect(range?.constant, 37);
  });
}
