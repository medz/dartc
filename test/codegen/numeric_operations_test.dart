import 'package:dartc/codegen.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

void main() {
  for (final CodeGenerator generator in [
    Arm64CodeGenerator(const Target(.linux, .arm64)),
    X64CodeGenerator(const Target(.linux, .x64)),
  ]) {
    test(
      '${generator.target} checks conversion dependencies only for non-integers',
      () {
        for (final input in [ValueType.integer, ValueType.floating]) {
          final target = FunctionTarget(
            Uri.parse('memory:conversion'),
            'convert',
            .integer,
            [input],
          );
          final entry = Block(target.parameterTypes);
          entry.finish(
            Return(entry.emit(NumericToInt(entry.parameters.single, .round))),
          );
          final program = IrProgram([], [
            IrFunction(target, [entry]),
          ]);
          if (input == ValueType.integer) {
            expect(
              generator.generate(program, definitions: [target]).sections,
              isNotEmpty,
            );
          } else {
            expect(
              () => generator.generate(program, definitions: [target]),
              throwsA(
                isA<UnsupportedError>().having(
                  (error) => error.message,
                  'dependency',
                  contains('UnsupportedError constructor'),
                ),
              ),
            );
          }
        }
      },
    );

    test('${generator.target} requires shift error constructor bodies', () {
      final target = FunctionTarget(
        Uri.parse('memory:shift'),
        'shift',
        .integer,
        [.integer, .integer],
      );
      final entry = Block(target.parameterTypes);
      entry.finish(
        Return(
          entry.emit(
            IntBinary(.shiftLeft, entry.parameters[0], entry.parameters[1]),
          ),
        ),
      );
      final program = IrProgram([], [
        IrFunction(target, [entry]),
      ]);
      expect(
        () => generator.generate(program, definitions: [target]),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'dependency',
            contains('ArgumentError constructor'),
          ),
        ),
      );
    });

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
        generator.generate(program, definitions: [target]).sections,
        isNotEmpty,
      );
    });
  }
}
