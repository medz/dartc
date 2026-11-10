import 'dart:ffi';

import 'package:dartc/codegen.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import 'fixtures/aliases.dart';

void main() {
  test('typed native calls require no symbol binding or relocation', () {
    final callback = FfiTypes.resolve(
      NativePointerType(NativeFunctionType(NativeSignature(Int8, [Int64]))),
    );
    final target = FunctionTarget(
      .parse('memory:indirect'),
      'invoke',
      .integer,
      [callback, .integer],
    );
    final block = Block(target.parameterTypes);
    block.finish(
      Return(
        block.emit(NativeCall(block.parameters[0], [block.parameters[1]])),
      ),
    );
    final program = IrProgram([], [
      IrFunction(target, [block]),
    ]);
    for (final os in OperatingSystem.values) {
      for (final CodeGenerator generator in [
        Arm64CodeGenerator(Target(os, .arm64)),
        X64CodeGenerator(Target(os, .x64)),
      ]) {
        final module = generator.generate(program, definitions: [target]);
        expect(module.relocations, isEmpty);
        expect(module.symbols.single.name, 'invoke');
        expect(module.sections.single.bytes, isNotEmpty);
      }
    }
  });

  test(
    'definition selection and native exports are separate checked inputs',
    () {
      final arithmeticProgram = arithmetic();
      final callee = arithmeticProgram.functions.first.target;
      final entry = FunctionTarget(
        .parse('memory:caller'),
        'caller',
        .integer,
        [],
      );
      final block = Block([]);
      final result = block.emit(
        DirectCall(callee, [Constant.integer(19), Constant.integer(23)]),
      );
      block.emit(
        DirectCall(callee, [Constant.integer(1), Constant.integer(2)]),
      );
      block.finish(Return(result));
      final program = IrProgram([], [
        ...arithmeticProgram.functions,
        IrFunction(entry, [block]),
      ]);
      for (final CodeGenerator generator in [
        Arm64CodeGenerator(const Target(.linux, .arm64)),
        X64CodeGenerator(const Target(.linux, .x64)),
      ]) {
        expect(
          () => generator.generate(program, definitions: [entry]),
          throwsArgumentError,
        );
        final withSupport = Block();
        withSupport.emit(
          NumericRoundToDouble(const Constant.floating(1.5), .round),
        );
        withSupport.finish(
          Return(
            withSupport.emit(
              DirectCall(callee, [
                const Constant.integer(1),
                const Constant.integer(2),
              ]),
            ),
          ),
        );
        expect(
          () => generator.generate(
            IrProgram([], [
              ...arithmeticProgram.functions,
              IrFunction(entry, [withSupport]),
            ]),
            definitions: [entry],
          ),
          throwsArgumentError,
        );
        expect(
          () => generator.generate(
            program,
            definitions: [callee],
            exports: {
              entry: NativeExport(
                'caller',
                NativeSignature(Int64, List.filled(0, Int64)),
              ),
            },
          ),
          throwsArgumentError,
        );
        expect(
          () => generator.generate(
            program,
            definitions: [callee],
            exports: {
              callee: NativeExport(
                'add',
                NativeSignature(Int64, List.filled(0, Int64)),
              ),
            },
          ),
          throwsArgumentError,
        );
        final module = generator.generate(
          program,
          definitions: [entry, callee],
        );
        expect(
          module.symbols.every(
            (symbol) => symbol.binding == .local && !symbol.exported,
          ),
          isTrue,
        );
        expect(module.relocations.map((r) => r.symbol), [1, 1]);
      }
    },
  );

  test('backends reject incompatible targets', () {
    expect(
      () => Arm64CodeGenerator(const .new(.linux, .x64)),
      throwsArgumentError,
    );
    expect(
      () => X64CodeGenerator(const .new(.macos, .arm64)),
      throwsArgumentError,
    );
  });

  test('one backend can generate independent modules repeatedly', () {
    final program = arithmetic();
    final exports = {
      for (final f in program.functions)
        f.target: NativeExport(
          f.target.name,
          NativeSignature(Int64, List.filled(2, Int64)),
        ),
    };
    for (final CodeGenerator generator in [
      Arm64CodeGenerator(const Target(.linux, .arm64)),
      X64CodeGenerator(const Target(.linux, .x64)),
    ]) {
      final first = generator.generate(
        program,
        definitions: exports.keys,
        exports: exports,
      );
      final second = generator.generate(
        program,
        definitions: exports.keys,
        exports: exports,
      );
      expect(second.sections.single.bytes, first.sections.single.bytes);
      expect(second.target, generator.target);
      expect(
        second.symbols.map((s) => s.name),
        exports.values.map((e) => e.symbol),
      );
    }
  });
}
