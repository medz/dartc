import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

void main() {
  final uri = Uri.parse('memory:entry-lifetime');
  for (final reenter in [false, true]) {
    for (final throws in [false, true]) {
      test('final module exit, native reentry=$reenter, throw=$throws', () {
        final completed = GlobalVariable(uri, 'completed', .boolean.nullable);
        final working = GlobalVariable(uri, 'working', .boolean.nullable);
        final installed = GlobalVariable(uri, 'installed', .boolean.nullable);
        final observe = FunctionTarget(uri, 'read', .boolean.nullable, []);
        final install = FunctionTarget(uri, 'install', .voidType, []);
        final finish = FunctionTarget(uri, 'close', .voidType, []);
        final host = FunctionTarget(uri, 'host', .voidType, []);
        final read = Block();
        final stage = read.emit(LoadGlobal(working));
        read.finish(Return(read.emit(LoadGlobal(completed))));
        final set = Block();
        set.emit(StoreGlobal(installed, const Constant.boolean(true)));
        set.finish(const Return());
        final close = Block();
        final saved = close.emit(LoadGlobal(installed));
        close.emit(StoreGlobal(working, const Constant.boolean(true)));
        if (reenter) close.emit(DirectCall(host, []));
        close.emit(StoreGlobal(completed, const Constant.boolean(true)));
        close.finish(
          throws ? Throw(const Constant.string('closed')) : const Return(),
        );
        final program = IrProgram(
          [],
          [
            IrFunction(observe, [read]),
            IrFunction(install, [set]),
            IrFunction(finish, [close]),
          ],
          externals: [
            IrExternal(
              host,
              effects: {Effect.callsUserCode},
              memory: const .unchanged(),
            ),
          ],
          globals: [completed, working, installed],
        );
        final facts = ProgramFlow(
          program,
          const [],
          openEntries: [observe, install, finish],
          terminalEntry: finish,
        ).facts;
        Object? scalar(Constant c) => (c as ScalarConstant).value;
        expect(facts.valueOf(saved).constants.map(scalar), contains(true));
        expect(
          facts.valueOf(stage).constants.map(scalar).contains(true),
          reenter,
        );
        expect(facts.returnedBy(observe).constants.map(scalar), [null]);
      });
    }
  }
}
