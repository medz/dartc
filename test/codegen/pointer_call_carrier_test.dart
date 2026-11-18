import 'package:dartc/abi.dart';
import 'package:dartc/codegen.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/target.dart';
import 'package:dartc/src/codegen/checked_casts.dart';
import 'package:dartc/src/codegen/heap_plan.dart';
import 'package:dartc/src/codegen/member_calls.dart';
import 'package:dartc/src/codegen/program_selection.dart';
import 'package:dartc/src/codegen/storage_access.dart';
import 'package:test/test.dart';

void main() {
  test('a retained ordinary call transports the proven pointer address', () {
    final pointer = FfiTypes.int64Pointer;
    final helper = FunctionTarget(null, 'pointerConsumer', .integer, [pointer]);
    final body = Block(helper.parameterTypes);
    body.finish(Return(body.emit(PointerAddress(body.parameters.single))));
    final root = FunctionTarget(null, 'root', .integer, [.integer]);
    final entry = Block(root.parameterTypes);
    final value = entry.emit(
      PointerFromAddress(entry.parameters.single, pointer),
    );
    entry.finish(Return(entry.emit(DirectCall(helper, [value]))));
    final program = IrProgram([], [
      IrFunction(root, [entry]),
      IrFunction(helper, [body]),
    ]);
    for (final platform in [
      const Target(.linux, .arm64),
      const Target(.linux, .x64),
    ]) {
      final layout = ProgramLayout(
        program.classes,
        functions: program.functions,
        nativeLayout: NativeLayout(platform),
      );
      final facts = ProgramFlow(
        program,
        [],
        openEntries: [root],
        memoryLayout: layout,
      ).facts;
      final prepared = ProgramPreparation(
        platform,
        program,
        boundaries: NativeBoundaries(program, roots: [root]),
      ).prepare(facts);
      expect(prepared, isA<PreparedProgram>());
      expect(prepared.definitions, {root, helper});
      final generator = platform.architecture == .arm64
          ? Arm64CodeGenerator(platform)
          : X64CodeGenerator(platform);
      expect(
        generator.generate(prepared).symbols.map((symbol) => symbol.name),
        contains('pointerConsumer'),
      );
    }
  });
  for (final change in [
    'none',
    'argument',
    'target',
    'receiver',
    'field',
    'conversion',
  ]) {
    test('call proof rejects altered pointer $change transport', () {
      final pointer = FfiTypes.int64Pointer;
      final helper = FunctionTarget(null, 'consume', .integer, [pointer]);
      final other = FunctionTarget(null, 'different', .integer, [pointer]);
      IrFunction consumer(FunctionTarget target) {
        final block = Block(target.parameterTypes);
        block.finish(
          Return(block.emit(PointerAddress(block.parameters.single))),
        );
        return IrFunction(target, [block]);
      }

      final root = FunctionTarget(null, 'root', .integer, [.integer, .integer]);
      final entry = Block(root.parameterTypes);
      final value = entry.emit(
        PointerFromAddress(entry.parameters.first, pointer),
      );
      final second = entry.emit(
        PointerFromAddress(entry.parameters.last, pointer),
      );
      final call = entry.emit(DirectCall(helper, [value]));
      entry.finish(Return(call));
      final source = IrFunction(root, [entry]);
      final bodies = [source, consumer(helper), consumer(other)];
      final program = IrProgram([], bodies);
      final layout = ProgramLayout(
        [],
        functions: bodies,
        nativeLayout: NativeLayout(const Target(.linux, .arm64)),
      );
      final facts = ProgramFlow(
        program,
        [],
        openEntries: [root],
        memoryLayout: layout,
      ).facts;
      final selection = ProgramSelection(
        layout,
        HeapPlan(),
        CheckedCasts(failure: null),
        MemberCalls(program, facts.definitions, callTypes: facts),
        layout.instances,
      );
      for (final body in bodies) {
        selection.include(body);
      }
      final selected = selection.functions[root]!;
      final physical = selected.invocations.keys.single;
      switch (change) {
        case 'argument':
          selected.operands[physical] = [entry.parameters.last];
        case 'target':
          selected.invocations[physical] = other;
        case 'receiver':
          selected.operands[physical] = [
            StorageRead(layout.pointers.address, second),
          ];
        case 'field':
          selected.operands[physical] = [
            StorageRead(
              InstanceField(
                ClassType(null, 'Unrelated'),
                'differentSlot',
                .integer,
              ),
              value,
            ),
          ];
        case 'conversion':
          selected.operands[physical] = [UncheckedCast(value, .integer)];
      }
      expect(selection.close(persistent: false, roots: {root}), isEmpty);
      expect(
        selection.implicitCalls,
        change == 'none' ? isEmpty : {change == 'target' ? other : helper},
      );
    });
  }
}
