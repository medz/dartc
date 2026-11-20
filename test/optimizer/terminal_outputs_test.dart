import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

void main() {
  final uri = Uri.parse('memory:terminal-output-ownership');
  for (final throwing in [false, true]) {
    for (final role in ['terminal', 'ordinary', 'also-direct']) {
      test('retained observer, exit $role, throwing=$throwing', () {
        final after = GlobalVariable(uri, 'post', .boolean.nullable);
        final staged = GlobalVariable(uri, 'pre', .boolean.nullable);
        final callback = FunctionTarget(uri, 'observe', .boolean.nullable, []);
        final cb = Block();
        final progress = cb.emit(LoadGlobal(staged));
        final tail = cb.emit(LoadGlobal(after));
        cb.finish(Return(tail));
        final install = FunctionTarget(uri, 'install', .voidType, []);
        final holder = FunctionTarget(uri, 'retain', .voidType, [
          callback.signature,
        ]);
        final installBlock = Block();
        installBlock.emit(DirectCall(holder, [FunctionConstant(callback)]));
        installBlock.finish(const Return());
        final host = FunctionTarget(uri, 'reenter', .voidType, []);
        final cleanup = FunctionTarget(uri, 'cleanup', .voidType, []);
        final close = Block();
        close.emit(StoreGlobal(staged, const Constant.boolean(true)));
        close.emit(DirectCall(host, []));
        close.emit(StoreGlobal(after, const Constant.boolean(true)));
        close.finish(
          throwing ? Throw(const Constant.integer(37)) : const Return(),
        );
        final ordinary = FunctionTarget(uri, 'invokeSameBody', .voidType, []);
        final act = Block();
        act.emit(DirectCall(cleanup, []));
        act.finish(const Return());
        final p = IrProgram(
          [],
          [
            IrFunction(install, [installBlock]),
            IrFunction(cleanup, [close]),
            IrFunction(callback, [cb]),
            IrFunction(ordinary, [act]),
          ],
          globals: [after, staged],
          externals: [
            IrExternal(holder, effects: const {}, memory: const .unchanged()),
            IrExternal(
              host,
              effects: {Effect.callsUserCode},
              memory: const .unchanged(),
            ),
          ],
        );
        final f = ProgramFlow(
          p,
          [],
          openEntries: [install, cleanup, if (role == 'also-direct') ordinary],
          terminalEntry: role == 'ordinary' ? null : cleanup,
        ).facts;
        bool saw(Value op) => f
            .valueOf(op)
            .constants
            .whereType<ScalarConstant>()
            .any((c) => c.value == true);
        expect(saw(progress), isTrue);
        expect(saw(tail), role != 'terminal');
      });
    }
    test('callable available only at terminal exit, throwing=$throwing', () {
      final cb = FunctionTarget(uri, 'unavailable', .integer, []);
      final leaf = Block()..finish(const Return(Constant.integer(91)));
      final cleanup = FunctionTarget(uri, 'end', cb.signature, []);
      final e = Block()
        ..finish(
          throwing ? Throw(FunctionConstant(cb)) : Return(FunctionConstant(cb)),
        );
      final f = ProgramFlow(
        IrProgram([], [
          IrFunction(cleanup, [e]),
          IrFunction(cb, [leaf]),
        ]),
        [],
        openEntries: [cleanup],
        terminalEntry: cleanup,
      ).facts;
      expect(f.definitions.contains(cb), isFalse);
    });
  }
}
