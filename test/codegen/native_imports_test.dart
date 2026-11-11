import 'dart:ffi';

import 'package:dartc/abi.dart';
import 'package:dartc/codegen.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/runtime.dart';

void main() {
  setUpAll(prepareRuntime);
  final library = Uri.parse('memory:native-imports');
  final first = FunctionTarget(library, 'first', .integer, [.integer]);
  final second = FunctionTarget(library, 'second', .integer, [.integer]);
  final caller = FunctionTarget(library, 'caller', .integer, [.integer]);
  final entry = Block(caller.parameterTypes);
  final a = entry.emit(DirectCall(first, entry.parameters));
  final b = entry.emit(DirectCall(second, [a]));
  entry.finish(Return(b));
  final program = IrProgram(
    [],
    [
      IrFunction(caller, [entry]),
    ],
    externals: [IrExternal(first), IrExternal(second)],
  );
  final binding = NativeImport('actual_native', NativeSignature(Int8, [Int8]));

  for (final os in OperatingSystem.values) {
    for (final arch in Architecture.values) {
      final target = Target(os, arch);
      final CodeGenerator generator = arch == .arm64
          ? Arm64CodeGenerator(target)
          : X64CodeGenerator(target);
      test(
        '$target binds declaration identities and deduplicates native symbols',
        () {
          final module = generator.generate(
            program,
            heapCapacity: heapCapacity,
            definitions: [first, caller, second],
            imports: {first: binding, second: binding},
            exports: {
              caller: NativeExport('caller', NativeSignature(Int8, [Int8])),
            },
          );
          expect(module.imports, [target.nativeSymbol('actual_native')]);
          expect(module.symbols, hasLength(4));
          expect(
            module.relocations.map((r) => r.symbol),
            unorderedEquals([0, 2, 1, 4, 4]),
          );
          expect(
            module.symbols
                .take(3)
                .every((s) => !s.exported && s.binding == .local),
            isTrue,
          );
          expect(module.symbols.last.exported, isTrue);
        },
      );

      test('$target rejects missing, mismatched and non-external bindings', () {
        final definitions = [first, caller, second];
        expect(
          () => generator.generate(
            program,
            heapCapacity: heapCapacity,
            definitions: definitions,
          ),
          throwsArgumentError,
        );
        for (final invalid in [
          NativeSignature(Double, [Int64]),
          NativeSignature(Int64, []),
        ]) {
          expect(
            () => generator.generate(
              program,
              heapCapacity: heapCapacity,
              definitions: definitions,
              imports: {first: NativeImport('wrong', invalid), second: binding},
            ),
            throwsArgumentError,
          );
        }
        expect(
          () => generator.generate(
            program,
            heapCapacity: heapCapacity,
            definitions: definitions,
            imports: {first: binding, second: binding, caller: binding},
          ),
          throwsArgumentError,
        );
        final callback = NativePointerType(
          NativeFunctionType(NativeSignature(Int64, [Int8])),
        );
        final withPointer = FunctionTarget(library, 'withPointer', .integer, [
          FfiTypes.resolve(callback),
        ]);
        final pointerProgram = IrProgram(
          [],
          [],
          externals: [IrExternal(withPointer)],
        );
        expect(
          () => generator.generate(
            pointerProgram,
            heapCapacity: heapCapacity,
            definitions: [withPointer],
            imports: {
              withPointer: NativeImport(
                'other_signature',
                NativeSignature.types(NativeScalarType(Int64), [
                  NativePointerType(
                    NativeFunctionType(NativeSignature(Int64, [Uint8])),
                  ),
                ]),
              ),
            },
          ),
          throwsArgumentError,
        );
        expect(
          () => generator.generate(
            program,
            heapCapacity: heapCapacity,
            definitions: [caller],
            imports: {first: binding},
          ),
          throwsArgumentError,
        );
        expect(
          () => generator.generate(
            program,
            heapCapacity: heapCapacity,
            definitions: definitions,
            imports: {first: binding, second: binding},
            exports: {first: NativeExport('first', binding.signature)},
          ),
          throwsArgumentError,
        );
      });
    }
  }
}
