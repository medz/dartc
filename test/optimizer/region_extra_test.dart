import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

import 'region_origin_test.dart' as region;
import '../support/ir_interpreter.dart';

void main() {
  for (final throws in [false, true]) {
    test(
      'user receiver on a feasible alternative retains equality effects and ${throws ? "exception" : "result"}',
      () {
        final uri = Uri.parse('memory:external-address-equality');
        final owner = ClassType(uri, 'Checker');
        final changed = GlobalVariable(uri, 'changed', .integer, isLate: true);
        final operator = FunctionTarget(
          uri,
          '==',
          .boolean,
          [.object],
          owner: owner,
          kind: .method,
        );
        final implementation = Block(operator.parameterTypes);
        final write = implementation.emit(
          StoreGlobal(changed, const Constant.integer(9)),
        );
        implementation.finish(
          throws
              ? Throw(const Constant.string('observer'))
              : const Return(Constant.boolean(true)),
        );
        final choose = FunctionTarget(uri, 'choose', .object, [.boolean]);
        final start = Block(choose.parameterTypes),
            split = Block(),
            foreign = Block(),
            obj = Block(),
            bad = Block();
        final base = start.emit(
          DirectCall(region.map, [const Constant.integer(32)]),
        );
        start.finish(
          Branch(start.emit(Equals(base, region.zero)), Jump(bad), Jump(split)),
        );
        bad.finish(Throw(const Constant.string('no mapping')));
        split.finish(Branch(start.parameters.single, Jump(foreign), Jump(obj)));
        foreign.finish(
          Return(
            foreign.emit(IntBinary(.add, base, const Constant.integer(8))),
          ),
        );
        obj.finish(Return(ObjectConstant(owner, {})));
        final root = FunctionTarget(uri, 'root', .integer, [.boolean]);
        final main = Block(root.parameterTypes),
            yes = Block(),
            no = Block(),
            handler = Block(),
            branch = Block([ValueType.boolean]);
        main.emit(StoreGlobal(changed, const Constant.integer(1)));
        final receiver = main.emit(DirectCall(choose, main.parameters));
        final test = Equals(receiver, region.zero);
        main.finish(
          Invoke(test, onReturn: Jump(branch, [test]), onThrow: Jump(handler)),
        );
        branch.finish(Branch(branch.parameters.single, Jump(yes), Jump(no)));
        yes.finish(Return(yes.emit(LoadGlobal(changed))));
        no.finish(Return(no.emit(LoadGlobal(changed))));
        final errorValue = handler.emit(LoadGlobal(changed));
        handler.finish(
          Return(
            handler.emit(
              IntBinary(.add, errorValue, const Constant.integer(100)),
            ),
          ),
        );
        final graph = IrProgram(
          [
            IrClass(owner, [], members: [operator]),
          ],
          [
            IrFunction(root, [main, yes, no, handler, branch]),
            IrFunction(choose, [start, split, foreign, obj, bad]),
            IrFunction(operator, [implementation]),
          ],
          globals: [changed],
          externals: region.externals,
        );
        final f = ProgramFlow(graph, [
          (target: root, arguments: [FlowValue.unknown(.boolean)]),
        ], memoryLayout: region.Layout()).facts;
        expect(test.mayCallUserCode, isTrue);
        expect(f.activationsOf(operator), isNotEmpty);
        expect(f.reachesOperation(write), isTrue);
        final interpreter = IrInterpreter(graph, {
          (region.uri, 'map'): (int _) => 4096,
        });
        expect(
          interpreter.run(graph.functions.first, [false]),
          throws ? 109 : 9,
        );
        expect(interpreter.run(graph.functions.first, [true]), 1);
        if (throws) {
          expect(f.reachesBlock(handler), isTrue);
        }
      },
    );
  }

  test(
    'two independently successful mappings do not identify their addresses',
    () {
      final root = FunctionTarget(null, 'compare', .boolean, []);
      final a = Block(),
          b = Block(),
          ok = Block([ValueType.integer]),
          failed = Block();
      final first = a.emit(
        DirectCall(region.map, [const Constant.integer(16)]),
      );
      a.finish(
        Branch(a.emit(Equals(first, region.zero)), Jump(failed), Jump(b)),
      );
      final second = b.emit(
        DirectCall(region.map, [const Constant.integer(16)]),
      );
      b.finish(
        Branch(
          b.emit(Equals(second, region.zero)),
          Jump(failed),
          Jump(ok, [second]),
        ),
      );
      failed.finish(Throw(const Constant.string('no mapping')));
      final left = ok.emit(IntBinary(.add, first, const Constant.integer(8)));
      final right = ok.emit(
        IntBinary(.add, ok.parameters.single, const Constant.integer(8)),
      );
      final eq = ok.emit(Equals(left, right));
      ok.finish(Return(eq));
      final graph = IrProgram([], [
        IrFunction(root, [a, b, ok, failed]),
      ], externals: region.externals);
      final f = ProgramFlow(graph, [
        (target: root, arguments: <FlowValue>[]),
      ], memoryLayout: region.Layout()).facts;
      expect(region.truth(f, eq), isNot(true));
      expect(
        f.valueOf(left).addresses.single.base,
        isNot(f.valueOf(right).addresses.single.base),
      );
    },
  );

  test(
    'unsigned endpoint arithmetic distinguishes last byte from one past',
    () {
      for (var bits = 2; bits <= 8; bits++) {
        final mod = 1 << bits;
        for (var base = 1; base < mod; base++) {
          for (var length = 1; length <= mod - base; length++) {
            for (var delta = 0; delta < length; delta++) {
              if ((base + delta) % mod == 0) fail('interior wraps to zero');
            }
          }
        }
      }
      final modulus = BigInt.one << 64, base = modulus - BigInt.from(32);
      expect((base + BigInt.from(31)) % modulus, modulus - BigInt.one);
      expect((base + BigInt.from(32)) % modulus, BigInt.zero);
      expect((BigInt.from(8) + BigInt.from(-8)) % modulus, BigInt.zero);
      expect((-32 + 32).toUnsigned(64), 0);
    },
  );
}
