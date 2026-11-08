import 'package:dartc/codegen.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import 'fixtures/aliases.dart';

void main() {
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
