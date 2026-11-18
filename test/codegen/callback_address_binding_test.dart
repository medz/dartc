import 'dart:ffi';

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
  for (final change in ['none', 'missing', 'provider', 'origin', 'arguments']) {
    test('callback address proof checks its exact $change binding', () {
      final callback = FunctionTarget(null, 'callback', .integer, []);
      final target = StaticCallbackTarget(
        callback,
        FunctionType(FfiTypes.scalarTypes[Int64]!, []),
        exceptionalReturn: const Constant.integer(-1),
      );
      final provider = FunctionTarget(null, 'provider', .integer, []);
      final other = FunctionTarget(null, 'otherProvider', .integer, []);
      final root = FunctionTarget(null, 'root', .integer, []);
      final entry = Block();
      final address = entry.emit(NativeCallbackAddress(target));
      entry.finish(Return(address));
      final source = IrFunction(root, [entry]);
      final callbackBody = IrFunction(callback, [
        Block()..finish(const Return(Constant.integer(42))),
      ]);
      final program = IrProgram(
        [],
        [source, callbackBody],
        externals: [IrExternal(provider), IrExternal(other)],
        nativeBoundaries: change == 'missing'
            ? null
            : NativeBoundaryBindings(
                callbacks: {target: (address: provider, target: callback)},
              ),
      );
      final layout = ProgramLayout(
        [],
        nativeLayout: NativeLayout(const Target(.linux, .arm64)),
      );
      final facts = ProgramFlow(
        program,
        [],
        openEntries: [root],
        nativeEntries: {target: callback},
      ).facts;
      final selection = ProgramSelection(
        layout,
        HeapPlan(),
        CheckedCasts(),
        MemberCalls(program, facts.definitions, callTypes: facts),
        layout.instances,
        callbacks: {target: provider},
      );
      selection.include(source);
      selection.include(callbackBody);
      final selected = selection.functions[root]!;
      if (change == 'provider') selected.invocations[address] = other;
      if (change == 'origin') {
        selected.callOrigins[address] = NativeCallbackAddress(target);
      }
      if (change == 'arguments') {
        selected.operands[address] = [const Constant.integer(1)];
      }
      selection.close(persistent: false, roots: {root});
      expect(
        selection.implicitCalls,
        change == 'none'
            ? isEmpty
            : contains(change == 'provider' ? other : provider),
      );
    });
  }
}
