import 'dart:ffi';

import 'package:dartc/frontend.dart';
import 'package:dartc/ir.dart';
import 'package:test/test.dart';

import '../../support/ir_interpreter.dart';

void main() {
  test(
    'FFI lowering uses declarations, preserving user classes and extensions',
    () async {
      final result = await AnalysisSession([
        'test/compiler/fixtures/pointers.dart',
        'test/compiler/fixtures/pointer_helpers.dart',
      ]).use(Lowering().lower);
      final functions = {
        for (final function in result.program.functions)
          if (function.target.owner == null) function.target.name: function,
      };
      Iterable<Instruction> instructions(String name) =>
          functions[name]!.blocks.expand((block) => block.instructions);
      expect(
        instructions('fromAddress').whereType<PointerFromAddress>(),
        hasLength(1),
      );
      expect(instructions('address').whereType<PointerAddress>(), hasLength(1));
      expect(instructions('read').whereType<LoadNativeInt64>(), hasLength(1));
      expect(instructions('write').whereType<StoreNativeInt64>(), hasLength(1));
      expect(
        instructions('ordinaryPointer').whereType<Construct>(),
        hasLength(1),
      );
      expect(
        instructions('customMember').whereType<DirectCall>(),
        hasLength(1),
      );
      expect(
        instructions('customMember').whereType<LoadNativeInt64>(),
        isEmpty,
      );
      final runner = IrInterpreter(result.program, {});
      for (final address in [
        0,
        1,
        -1,
        -9223372036854775808,
        9223372036854775807,
      ]) {
        final pointer = runner.run(functions['fromAddress']!, [address]);
        expect(pointer, Pointer<Int64>.fromAddress(address));
        expect(runner.run(functions['address']!, [pointer]), address);
        expect(runner.run(functions['declaredMember']!, [pointer]), 73);
        expect(runner.run(functions['ordinaryPointer']!, [address]), address);
      }
    },
  );
}
