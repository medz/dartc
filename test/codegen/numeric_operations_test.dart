import 'package:dartc/compiler.dart';
import 'package:dartc/codegen.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/runtime.dart';

void main() {
  setUpAll(prepareRuntime);
  for (final CodeGenerator generator in [
    Arm64CodeGenerator(const Target(.linux, .arm64)),
    X64CodeGenerator(const Target(.linux, .x64)),
  ]) {
    test(
      '${generator.target} rounds to double without an error dependency',
      () {
        for (final type in [
          ValueType.integer,
          ValueType.floating,
          ValueType.number,
        ]) {
          for (final rounding in IntegerRounding.values) {
            final target = FunctionTarget(
              Uri.parse('memory:rounding'),
              'round',
              .floating,
              [type],
            );
            final entry = Block(target.parameterTypes);
            entry.finish(
              Return(
                entry.emit(
                  NumericRoundToDouble(entry.parameters.single, rounding),
                ),
              ),
            );
            final program = IrProgram([], [
              IrFunction(target, [entry]),
            ]);
            expect(
              generator
                  .generate(
                    Compiler(
                      generator.target,
                    ).prepare(program, runtime: heapRuntime, roots: [target]),
                  )
                  .sections,
              isNotEmpty,
            );
          }
        }
      },
    );

    test('${generator.target} reuses a supplied division exception class', () {
      final target = FunctionTarget(
        Uri.parse('memory:divide'),
        'divide',
        .integer,
        [.integer, .integer],
      );
      final entry = Block(target.parameterTypes);
      entry.finish(
        Return(
          entry.emit(
            IntBinary(
              .truncateDivide,
              entry.parameters[0],
              entry.parameters[1],
            ),
          ),
        ),
      );
      final program = IrProgram(
        [IrClass(CoreTypes.integerDivisionByZeroException, [])],
        [
          IrFunction(target, [entry]),
        ],
      );
      expect(
        generator
            .generate(
              Compiler(generator.target)
                  .prepare(program, runtime: heapRuntime, roots: [target]),
            )
            .sections,
        isNotEmpty,
      );
    });
  }
}
