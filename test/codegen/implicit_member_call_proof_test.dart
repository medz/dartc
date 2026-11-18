import 'package:dartc/abi.dart';
import 'package:dartc/codegen.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/target.dart';
import 'package:dartc/src/codegen/checked_casts.dart';
import 'package:dartc/src/codegen/heap_plan.dart';
import 'package:dartc/src/codegen/member_calls.dart';
import 'package:dartc/src/codegen/program_selection.dart';
import 'package:test/test.dart';

void main() {
  for (final change in ['none', 'argument', 'target', 'origin', 'arguments']) {
    test('implicit member proof preserves its actual $change call', () {
      final uri = Uri.parse('memory:implicit-member-proof');
      final owner = ClassType(
        uri,
        'Owner',
        interfaces: [CoreTypes.listOf(.integer)],
      );
      final otherOwner = ClassType(
        uri,
        'Other',
        interfaces: [CoreTypes.listOf(.integer)],
      );
      FunctionTarget getter(ClassType type) => FunctionTarget(
        uri,
        'length',
        .integer,
        [],
        owner: type,
        kind: .getter,
      );
      final member = getter(owner), other = getter(otherOwner);
      IrFunction body(FunctionTarget target) => IrFunction(target, [
        Block(target.parameterTypes)
          ..finish(const Return(Constant.integer(42))),
      ]);
      final root = FunctionTarget(uri, 'root', .integer, [owner, owner]);
      final entry = Block(root.parameterTypes);
      final observed = entry.emit(CollectionLength(entry.parameters.first));
      entry.finish(Return(observed));
      final source = IrFunction(root, [entry]);
      final program = IrProgram(
        [
          IrClass(owner, [], members: [member]),
          IrClass(otherOwner, [], members: [other]),
        ],
        [source, body(member), body(other)],
      );
      final facts = ProgramFlow(program, [], openEntries: [root]).facts;
      expect(facts.executionTargetsOf(observed), {member});
      final layout = ProgramLayout(
        [],
        nativeLayout: NativeLayout(const Target(.linux, .arm64)),
      );
      final selection = ProgramSelection(
        layout,
        HeapPlan(),
        CheckedCasts(),
        MemberCalls(program, facts.definitions, callTypes: facts),
        layout.instances,
      );
      for (final target in facts.definitions) {
        selection.include(program.implementationOf(target) as IrFunction);
      }
      final selected = selection.functions[root]!;
      final call = selected.invocations.keys.singleWhere(
        (op) => selected.invocations[op] == member,
      );
      if (change == 'argument') {
        selected.operands[call] = [entry.parameters.last];
      }
      if (change == 'arguments') {
        selected.operands[call] = [
          entry.parameters.first,
          const Constant.integer(1),
        ];
      }
      if (change == 'target') selected.invocations[call] = other;
      if (change == 'origin') {
        selected.callOrigins[call] = CollectionLength(entry.parameters.first);
      }
      selection.close(persistent: false, roots: {root});
      expect(
        selection.implicitCalls,
        change == 'none'
            ? isEmpty
            : contains(change == 'target' ? other : member),
      );
    });
  }
}
