import 'dart:ffi';

import 'package:dartc/abi.dart';
import 'package:dartc/codegen.dart';
import 'package:dartc/compiler.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

void main() {
  test(
    'fixed native blocks generate on all targets without a runtime allocator',
    () {
      final observe = FunctionTarget(null, 'observe', .integer, [
        .integer,
        .integer,
      ]);
      for (final size in [1, 17, 64, 77, 8193]) {
        final target = FunctionTarget(null, 'nativeStorage', .integer, []);
        final block = Block();
        final storage = block.emit(
          NativeLocalStorage(
            NativeArrayType(.of(Uint8), size),
            zeroInitialize: true,
          ),
        );
        final word = block.emit(NativeLocalStorage(.of(Int64)));
        block.finish(Return(block.emit(DirectCall(observe, [storage, word]))));
        final program = IrProgram(
          [],
          [
            IrFunction(target, [block]),
          ],
          externals: [
            IrExternal(
              observe,
              effects: const {Effect.readsStorage, Effect.writesStorage},
              capturesArguments: false,
            ),
          ],
        );
        for (final os in OperatingSystem.values) {
          for (final CodeGenerator generator in [
            Arm64CodeGenerator(Target(os, .arm64)),
            X64CodeGenerator(Target(os, .x64)),
          ]) {
            final module = generator.generate(
              Compiler(generator.target).prepare(
                program,
                roots: [target],
                imports: {
                  observe: NativeImport(
                    'observe',
                    NativeSignature(Int64, [Int64, Int64]),
                    isNonAllocating: true,
                  ),
                },
              ),
            );
            expect(module.imports, {generator.target.nativeSymbol('observe')});
            expect(
              module.symbols.map((symbol) => symbol.name),
              isNot(contains('allocate')),
            );
          }
        }
      }
    },
  );
}
