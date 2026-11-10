import 'package:dartc/codegen.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

void main() {
  for (final os in OperatingSystem.values) {
    for (final arch in Architecture.values) {
      final target = Target(os, arch);
      final CodeGenerator generator = arch == .arm64
          ? Arm64CodeGenerator(target)
          : X64CodeGenerator(target);
      test('$target rejects unsupported persistent global storage', () {
        for (final (type, late, final_) in [
          (ValueType.integer.nullable, false, false),
          (ValueType.number, false, false),
          (ValueType.integer, true, false),
          (ValueType.integer, false, true),
        ]) {
          final uri = Uri.parse('memory:globals');
          final init = FunctionTarget(uri, 'init', type, []);
          final initial = Block([])..finish(Return(const Constant.integer(7)));
          final global = GlobalVariable(
            uri,
            'value',
            type,
            isLate: late,
            isFinal: final_,
            initializer: init,
          );
          final read = FunctionTarget(uri, 'read', type, []);
          final entry = Block([]);
          entry.finish(Return(entry.emit(LoadGlobal(global))));
          final program = IrProgram(
            [],
            [
              IrFunction(init, [initial]),
              IrFunction(read, [entry]),
            ],
            globals: [global],
          );
          expect(
            () => generator.generate(
              program,
              definitions: program.reachableFrom([read]),
            ),
            throwsA(
              isA<UnsupportedError>().having(
                (e) => e.message,
                'reason',
                contains('global'),
              ),
            ),
          );
        }
      });
    }
  }
}
