import 'dart:ffi';

import 'package:dartc/codegen.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import 'fixtures/aliases.dart';

void main() {
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
