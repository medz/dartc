import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

void main() {
  final uri = Uri.parse('memory:string-flow');
  final codes = SequenceConstant(CoreTypes.listOf(.integer), [
    const Constant.integer(65),
    const Constant.integer(0x1f600),
    const Constant.integer(0xdfff),
  ]);
  for (final (operation, expected) in <(Instruction, Constant)>[
    (
      StringConcat(const Constant.string('73'), const Constant.string('')),
      const Constant.string('73'),
    ),
    (
      StringFromCharCode(const Constant.integer(0x1f600)),
      const Constant.string('\u{1f600}'),
    ),
    (
      StringFromCharCode(const Constant.integer(0xdfff)),
      const Constant.string('\udfff'),
    ),
    (
      StringCodeUnitAt(
        const Constant.string('A\u{1f600}'),
        const Constant.integer(2),
      ),
      const Constant.integer(0xde00),
    ),
    (
      StringFromCharCodes(codes, const Constant.integer(1)),
      const Constant.string('\u{1f600}\udfff'),
    ),
    (
      StringFromCharCodes(
        codes,
        const Constant.integer(1),
        const Constant.integer(2),
      ),
      const Constant.string('\u{1f600}'),
    ),
    (
      StringFromCharCodes(codes, const Constant.integer(5)),
      const Constant.string(''),
    ),
  ]) {
    test(
      'constant ${operation.runtimeType} preserves UTF-16 and disappears',
      () {
        final target = FunctionTarget(uri, 'value', operation.type, []);
        final entry = Block()
          ..emit(operation)
          ..finish(Return(operation));
        final body = IrFunction(target, [entry]);
        final program = IrProgram([], [body]);
        final facts = ProgramOptimizer(const [ProgramSimplification()])
            .run(program, [(target: target, arguments: [])]);
        final optimized = facts.program.implementationOf(target) as IrFunction;
        expect(
          facts.returnedBy(target).constant?.structuralKey,
          expected.structuralKey,
        );
        expect(optimized.entry.instructions, isEmpty);
        expect(
          IrInterpreter(facts.program, {}).run(optimized, []),
          IrInterpreter(program, {}).run(body, []),
        );
      },
    );
  }

  for (final operation in [
    StringCodeUnitAt(const Constant.string('x'), const Constant.integer(-1)),
    StringCodeUnitAt(const Constant.string('x'), const Constant.integer(1)),
    StringFromCharCode(const Constant.integer(0x110000)),
    StringFromCharCodes(codes, const Constant.integer(-1)),
  ]) {
    test('invalid ${operation.runtimeType} keeps its exception', () {
      final target = FunctionTarget(uri, 'invalid', operation.type, []);
      final entry = Block()
        ..emit(operation)
        ..finish(Return(operation));
      final body = IrFunction(target, [entry]);
      final program = IrProgram([], [body]);
      final facts = ProgramOptimizer(const [ProgramSimplification()])
          .run(program, [(target: target, arguments: [])]);
      final optimized = facts.program.implementationOf(target) as IrFunction;
      expect(
        () => IrInterpreter(program, {}).run(body, []),
        throwsArgumentError,
      );
      expect(
        () => IrInterpreter(facts.program, {}).run(optimized, []),
        throwsArgumentError,
      );
      expect(optimized.entry.instructions, isNotEmpty);
    });
  }

  test(
    'folded string values keep the effects that produced their operands',
    () {
    final output = FunctionTarget(uri, 'output', .voidType, [.integer]);
      final source = FunctionTarget(uri, 'source', .string, []);
      final sourceBody = Block()
      ..emit(DirectCall(output, [const Constant.integer(1)]))
        ..finish(const Return(Constant.string('73')));
      final target = FunctionTarget(uri, 'main', .string, []);
      final entry = Block();
      entry.finish(
        Return(
          entry.emit(
            StringConcat(
              entry.emit(DirectCall(source, [])),
              const Constant.string(''),
            ),
          ),
        ),
      );
      final program = IrProgram(
        [],
        [
          IrFunction(source, [sourceBody]),
          IrFunction(target, [entry]),
        ],
        externals: [IrExternal(output)],
      );
      final facts = ProgramOptimizer(const [ProgramSimplification()])
          .run(program, [(target: target, arguments: [])]);
      var calls = 0;
      expect(
        IrInterpreter(facts.program, {
          (uri, 'output'): (_) {
            calls++;
            return null;
          },
        }).run(facts.program.implementationOf(target) as IrFunction, []),
        '73',
      );
      expect(calls, 1);
      expect(facts.definitions, contains(output));
    },
  );
}
