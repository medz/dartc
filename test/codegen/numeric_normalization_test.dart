import 'package:dartc/codegen.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

void main() {
  test('target preparation rejects undisclosed numeric checks', () {
    final target = FunctionTarget(null, 'uncheckedInput', .integer, [
      .integer,
      .integer,
    ]);
    final block = Block(target.parameterTypes);
    block.finish(
      Return(
        block.emit(
          IntBinary(.truncateDivide, block.parameters[0], block.parameters[1]),
        ),
      ),
    );
    final source = IrProgram([], [
      IrFunction(target, [block]),
    ]);
    final boundaries = NativeBoundaries(source, roots: [target]);
    final preparation = ProgramPreparation(
      const Target(.linux, .arm64),
      source,
      boundaries: boundaries,
    );
    expect(
      () => preparation.prepare(
        CallTypeFlow(source, [
          target,
        ], instantiatedTypes: preparation.instantiatedTypes).facts,
      ),
      throwsStateError,
    );
  });

  test('numeric support uses actual arguments before representation', () {
    final target = FunctionTarget(null, 'halve', .integer, [.integer]);
    final entry = Block(target.parameterTypes);
    entry.finish(
      Return(
        entry.emit(
          IntBinary(
            .truncateDivide,
            entry.parameters.single,
            const Constant.integer(2),
          ),
        ),
      ),
    );
    final normalized = ProgramNormalization(
      IrProgram([], [
        IrFunction(target, [entry]),
      ]),
    ).run();
    expect(ProgramNormalization(normalized).run(), same(normalized));
    final facts =
        ProgramOptimizer(const [
          ProgramSimplification(),
          ProgramCallSpecialization(),
          ProgramStoragePromotion(),
          ProgramStorageElimination(),
          DirectCallInlining(),
        ]).run(normalized, [
          (target: target, arguments: [FlowValue.unknown(.integer)]),
        ]);
    final body = facts.program.implementationOf(target) as IrFunction;
    expect(facts.definitions, {target});
    expect(
      body.blocks.any((block) => block.end is Throw || block.end is Invoke),
      isFalse,
    );
    final quotient = body.entry.instructions.whereType<IntBinary>().single;
    expect(quotient.checked, isFalse);
    for (final value in [
      -0x8000000000000000,
      -9,
      -1,
      0,
      9,
      0x7fffffffffffffff,
    ]) {
      expect(IrInterpreter(facts.program, {}).run(body, [value]), value ~/ 2);
    }
  });

  for (final operator in <IntOperator>[.truncateDivide, .modulo, .remainder]) {
    test(
      'normalized ${operator.name} preserves overflow and zero exceptions',
      () {
        final target = FunctionTarget(null, operator.name, .integer, [
          .integer,
          .integer,
        ]);
        final entry = Block(target.parameterTypes);
        final returned = Block([.integer]), caught = Block();
        final operation = IntBinary(
          operator,
          entry.parameters[0],
          entry.parameters[1],
        );
        entry.finish(
          Invoke(
            operation,
            onReturn: Jump(returned, [operation]),
            onThrow: Jump(caught),
          ),
        );
        returned.finish(Return(returned.parameters.single));
        caught.finish(const Return(Constant.integer(12345)));
        final normalized = ProgramNormalization(
          IrProgram(
            [IrClass(CoreTypes.integerDivisionByZeroException, [])],
            [
              IrFunction(target, [entry, returned, caught]),
            ],
          ),
        ).run();
        final body = normalized.implementationOf(target) as IrFunction;
        for (final left in [
          -0x8000000000000000,
          -7,
          0,
          7,
          0x7fffffffffffffff,
        ]) {
          for (final right in [-0x8000000000000000, -3, -1, 0, 1, 3]) {
            final expected = right == 0
                ? 12345
                : switch (operator) {
                    .truncateDivide => left ~/ right,
                    .modulo => left % right,
                    .remainder => left.remainder(right),
                    _ => throw StateError('Unexpected test operator.'),
                  };
            expect(
              IrInterpreter(normalized, {}).run(body, [left, right]),
              expected,
              reason: '${operator.name}($left, $right)',
            );
          }
        }
      },
    );
  }

  test('double rounding normalizes without error constructor dependencies', () {
    for (final type in [
      ValueType.integer,
      ValueType.floating,
      ValueType.number,
    ]) {
      for (final rounding in IntegerRounding.values) {
        final target = FunctionTarget(null, 'round', .floating, [type]);
        final entry = Block(target.parameterTypes);
        entry.finish(
          Return(
            entry.emit(NumericRoundToDouble(entry.parameters.single, rounding)),
          ),
        );
        final program = ProgramNormalization(
          IrProgram([], [
            IrFunction(target, [entry]),
          ]),
        ).run();
        final body = program.implementationOf(target) as IrFunction;
        for (final value in <num>[
          if (type != ValueType.floating) ...[0, -7, 0x7fffffffffffffff],
          if (type != ValueType.integer) ...[
            0.0,
            -0.0,
            0.5,
            -0.5,
            double.maxFinite,
            double.infinity,
            double.nan,
          ],
        ]) {
          final expected = switch (rounding) {
            .truncate => value.truncateToDouble(),
            .floor => value.floorToDouble(),
            .ceil => value.ceilToDouble(),
            .round => value.roundToDouble(),
          };
          final actual =
              IrInterpreter(program, {}).run(body, [value]) as double;
          expect(actual, expected.isNaN ? isNaN : expected);
          if (expected == 0) expect(actual.isNegative, expected.isNegative);
        }
      }
    }
  });
}
