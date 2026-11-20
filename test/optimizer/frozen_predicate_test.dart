import 'dart:ffi' show Int64;

import 'package:dartc/abi.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

final class Layout implements FlowMemoryLayout {
  @override
  final nativeLayout = NativeLayout(const Target(.linux, .x64));
  @override
  ObjectLayout objectLayout(ClassType type) => ObjectLayout([.word]);
}

void main() {
  for (final kind in ['equal', 'less']) {
    test(
      'an unknown saved comparison with a changed carrier keeps its original outcomes ($kind)',
      () {
        final root = FunctionTarget(null, 'unknownPeer', .integer, [.integer]);
        final entry = Block(root.parameterTypes),
            branch = Block(),
            yes = Block(),
            no = Block();
        final v = entry.emit(MaterializeValue(const Constant.integer(10)));
        final x = entry.parameters.single;
        final cmp = entry.emit(
          kind == 'equal' ? Equals(v, x) : IntBinary(.lessThan, v, x),
        );
        entry.finish(Jump(branch));
        final addr = branch.emit(ReferenceAddress(v));
        final payload = branch.emit(
          IntBinary(
            .add,
            addr,
            const Constant.integer(ObjectHeader.fieldsOffset),
          ),
        );
        branch.emit(
          StoreNative(
            payload,
            NativeScalarType(Int64),
            const Constant.integer(20),
          ),
        );
        branch.finish(Branch(cmp, Jump(yes), Jump(no)));
        final onYes = yes.emit(IntBinary(.add, x, const Constant.integer(1)));
        final onNo = no.emit(IntBinary(.add, x, const Constant.integer(1)));
        yes.finish(Return(onYes));
        no.finish(Return(onNo));
        final graph = IrProgram(
          [IrClass(ValueType.integer, [])],
          [
            IrFunction(root, [entry, branch, yes, no]),
          ],
        );
        final facts = ProgramFlow(graph, [
          (
            target: root,
            arguments: [FlowValue.integerRange(FlowIntegerRange(5, 30))],
          ),
        ], memoryLayout: Layout()).facts;
        expect(facts.valueOf(cmp).constant, isNull);
        final y = facts.valueOf(onYes).integers!,
            n = facts.valueOf(onNo).integers!;
        print(
          'saved $kind yes=[${y.lower},${y.upper}] no=[${n.lower},${n.upper}]',
        );
        for (var i = 5; i <= 30; i++) {
          final actual = kind == 'equal' ? i == 10 : 10 < i;
          expect((actual ? y : n).contains(i + 1), isTrue, reason: 'input $i');
        }
      },
    );
  }

  test('immutable cross-block scalar comparisons retain both path bounds', () {
    final root = FunctionTarget(null, 'immutable', .integer, [.integer]);
    final entry = Block(root.parameterTypes),
        branch = Block(),
        yes = Block(),
        no = Block();
    final x = entry.parameters.single;
    final cond = entry.emit(
      IntBinary(.lessThan, x, const Constant.integer(10)),
    );
    entry.finish(Jump(branch));
    branch.finish(Branch(cond, Jump(yes), Jump(no)));
    final a = yes.emit(IntBinary(.add, x, const Constant.integer(1)));
    final b = no.emit(IntBinary(.add, x, const Constant.integer(1)));
    yes.finish(Return(a));
    no.finish(Return(b));
    final graph = IrProgram([], [
      IrFunction(root, [entry, branch, yes, no]),
    ]);
    final f = ProgramFlow(graph, [
      (
        target: root,
        arguments: [FlowValue.integerRange(FlowIntegerRange(5, 14))],
      ),
    ]).facts;
    expect(f.valueOf(a).integers, FlowIntegerRange(6, 10));
    expect(f.valueOf(b).integers, FlowIntegerRange(11, 15));
  });

  for (final known in [true, false, null]) {
    for (final negated in [false, true]) {
      test(
        'a saved is-test refines only surviving aliases (known=$known negated=$negated)',
        () {
          final root = FunctionTarget(null, 'check', .object, [
            ValueType.object,
          ]);
          final uri = Uri.parse('memory:frozen-type');
          final alias = GlobalVariable(uri, 'original', .object, isLate: true),
              overwritten = GlobalVariable(
                uri,
                'changed',
                .object,
                isLate: true,
              );
          final entry = Block(root.parameterTypes),
              later = Block(),
              yes = Block(),
              no = Block();
          final x = entry.parameters.single;
          entry.emit(StoreGlobal(alias, x));
          entry.emit(StoreGlobal(overwritten, x));
          final cond = entry.emit(
            TypeTest(x, ValueType.integer, negated: negated),
          );
          entry.finish(Jump(later));
          later.emit(
            StoreGlobal(overwritten, const Constant.string('changed after is')),
          );
          later.finish(Branch(cond, Jump(yes), Jump(no)));
          final y = yes.emit(LoadGlobal(alias)), n = no.emit(LoadGlobal(alias));
          final alteredYes = yes.emit(LoadGlobal(overwritten)),
              alteredNo = no.emit(LoadGlobal(overwritten));
          yes.finish(Return(y));
          no.finish(Return(n));
          final graph = IrProgram(
            [],
            [
              IrFunction(root, [entry, later, yes, no]),
            ],
            globals: [alias, overwritten],
          );
          final i = FlowValue.constant(const Constant.integer(7)),
              s = FlowValue.constant(const Constant.string('original'));
          final f = ProgramFlow(graph, [
            (
              target: root,
              arguments: [
                known == null
                    ? i.join(s)
                    : known
                    ? i
                    : s,
              ],
            ),
          ]).facts;
          for (final (outcome, target, read, changed) in [
            (true, yes, y, alteredYes),
            (false, no, n, alteredNo),
          ]) {
            final reaches = known == null || (known != negated) == outcome;
            expect(f.reachesBlock(target), reaches);
            if (!reaches) continue;
            expect(
              (f.valueOf(read).constant as ScalarConstant?)?.value,
              (outcome != negated) ? 7 : 'original',
            );
            expect(
              (f.valueOf(changed).constant as ScalarConstant?)?.value,
              'changed after is',
            );
          }
        },
      );
    }
  }

  for (final kind in ['notEqual', 'less']) {
    test('changing one operand after a frozen comparison cannot narrow its peer', () {
      final root = FunctionTarget(null, 'changedPeer', .integer, [.integer]);
      final entry = Block(root.parameterTypes), yes = Block(), no = Block();
      final v = entry.emit(MaterializeValue(const Constant.integer(10)));
      final x = entry.parameters.single;
      final addr = entry.emit(ReferenceAddress(v));
      final payload = entry.emit(
        IntBinary(
          .add,
          addr,
          const Constant.integer(ObjectHeader.fieldsOffset),
        ),
      );
      final cmp = entry.emit(
        kind == 'notEqual'
            ? Equals(v, x, negated: true)
            : IntBinary(.lessThan, v, x),
      );
      entry.emit(
        StoreNative(
          payload,
          NativeScalarType(Int64),
          const Constant.integer(20),
        ),
      );
      entry.finish(Branch(cmp, Jump(yes), Jump(no)));
      yes.finish(Return(x));
      no.finish(const Return(Constant.integer(-1)));
      final graph = IrProgram(
        [IrClass(ValueType.integer, [])],
        [
          IrFunction(root, [entry, yes, no]),
        ],
      );
      final f = ProgramFlow(graph, [
        (
          target: root,
          arguments: [FlowValue.integerRange(FlowIntegerRange(20, 30))],
        ),
      ], memoryLayout: Layout()).facts;
      final result = f.returnedBy(root).integers;
      print(
        'peer guard=$kind condition=${f.valueOf(cmp).constant?.structuralKey} result=[${result?.lower},${result?.upper}]',
      );
      expect(f.reachesBlock(yes), isTrue);
      expect(f.reachesBlock(no), isFalse);
      expect(result, FlowIntegerRange(20, 30));
    });
  }
  for (final kind in ['eq', 'ne', 'lt', 'ge']) {
    test('stored $kind result survives later scalar carrier payload write', () {
      final root = FunctionTarget(null, 'frozenPredicate', .integer, []);
      final entry = Block(), yes = Block(), no = Block();
      final v = entry.emit(MaterializeValue(const Constant.integer(42)));
      final addr = entry.emit(ReferenceAddress(v));
      final payload = entry.emit(
        IntBinary(
          .add,
          addr,
          const Constant.integer(ObjectHeader.fieldsOffset),
        ),
      );
      final test = entry.emit(switch (kind) {
        'eq' => Equals(v, const Constant.integer(42)),
        'ne' => Equals(v, const Constant.integer(42), negated: true),
        'lt' => IntBinary(.lessThan, v, const Constant.integer(20)),
        _ => IntBinary(.greaterOrEqual, v, const Constant.integer(20)),
      });
      entry.emit(
        StoreNative(
          payload,
          NativeScalarType(Int64),
          const Constant.integer(9),
        ),
      );
      entry.finish(Branch(test, Jump(yes), Jump(no)));
      yes.finish(Return(yes.emit(ProjectValue(v, ExecutionShape.word))));
      no.finish(
        Return(
          no.emit(
            IntBinary(
              .add,
              no.emit(ProjectValue(v, ExecutionShape.word)),
              const Constant.integer(100),
            ),
          ),
        ),
      );
      final graph = IrProgram(
        [IrClass(ValueType.integer, [])],
        [
          IrFunction(root, [entry, yes, no]),
        ],
      );
      final f = ProgramFlow(graph, [
        (target: root, arguments: <FlowValue>[]),
      ], memoryLayout: Layout()).facts;
      final outcome = kind == 'eq' || kind == 'ge';
      print(
        'guard=$kind frozen=${f.valueOf(test).constant?.structuralKey} yes=${f.reachesBlock(yes)} no=${f.reachesBlock(no)} result=${f.returnedBy(root).integers?.constant}',
      );
      expect(f.reachesBlock(yes), outcome);
      expect(f.reachesBlock(no), !outcome);
      expect(f.returnedBy(root).integers?.constant, outcome ? 9 : 109);
    });
  }
}
