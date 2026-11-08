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
            exports: {entry: NativeExport('caller', NativeSignature.int64(0))},
          ),
          throwsArgumentError,
        );
        expect(
          () => generator.generate(
            program,
            definitions: [callee],
            exports: {callee: NativeExport('add', NativeSignature.int64(0))},
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
        expect(module.relocations.single.symbol, 1);
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
        f.target: NativeExport(f.target.name, NativeSignature.int64(2)),
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
      expect(second.code, first.code);
      expect(second.target, generator.target);
      expect(
        second.symbols.map((s) => s.name),
        exports.values.map((e) => e.symbol),
      );
    }
  });
}
