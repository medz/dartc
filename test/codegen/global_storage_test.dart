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
      test('$target checks global storage and error-body dependencies', () {
        for (final (type, late, final_, initialized) in [
          (ValueType.integer.nullable, false, false, true),
          (ValueType.number, false, false, true),
          (ValueType.integer, true, false, false),
          (ValueType.integer, true, false, true),
          (ValueType.integer, false, true, true),
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
            initializer: initialized ? init : null,
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
          if (late && initialized) {
            expect(
              generator
                  .generate(program, definitions: program.reachableFrom([read]))
                  .sections,
              isNotEmpty,
            );
            continue;
          }
          expect(
            () => generator.generate(
              program,
              definitions: program.reachableFrom([read]),
            ),
            throwsA(
              isA<UnsupportedError>().having(
                (e) => e.message,
                'reason',
                contains(late || final_ ? 'LateError constructor' : 'global'),
              ),
            ),
          );
        }
      });
    }
  }
}
