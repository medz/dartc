import 'package:dartc/codegen.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

void main() {
  test(
    'incoming stack accesses reject offsets beyond their machine encoding',
    () {
      final generator = Arm64CodeGenerator(const Target(.linux, .arm64));
      for (final count in [4102, 4103]) {
        final target = FunctionTarget(
          .parse('memory:stack-limit'),
          'last',
          .integer,
          List.filled(count, .integer),
        );
        final entry = Block(target.parameterTypes);
        entry.finish(Return(entry.parameters.last));
        final program = IrProgram([], [
          IrFunction(target, [entry]),
        ]);
        if (count == 4102) {
          expect(
            generator.generate(program, definitions: [target]).code,
            isNotEmpty,
          );
        } else {
          expect(
            () => generator.generate(program, definitions: [target]),
            throwsRangeError,
          );
        }
      }
    },
  );
}
