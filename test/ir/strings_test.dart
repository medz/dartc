import 'package:dartc/ir.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

void main() {
  test('string access validates operands and preserves effects', () {
    const text = Constant.string('');
    final length = StringLength(text);
    final unit = StringCodeUnitAt(text, const Constant.integer(0));
    expect(length.type, ValueType.integer);
    expect(length.effects, {Effect.readsStorage});
    expect(unit.type, ValueType.integer);
    expect(unit.effects, {Effect.readsStorage, Effect.mayThrow});
    expect(() => StringLength(const Constant.nullValue()), throwsArgumentError);
    expect(
      () => StringCodeUnitAt(text, const Constant.floating(0)),
      throwsArgumentError,
    );
  });

  test(
    'code-unit access preserves UTF-16 units and rejects invalid indices',
    () {
      final target = FunctionTarget(
        Uri.parse('memory:strings'),
        'read',
        .integer,
        [.string, .integer],
      );
      final entry = Block(target.parameterTypes);
      entry.finish(
        Return(
          entry.emit(
            StringCodeUnitAt(entry.parameters[0], entry.parameters[1]),
          ),
        ),
      );
      final function = IrFunction(target, [entry]);
      final runner = IrInterpreter(IrProgram([], [function]), {});
      const text = 'A\u0000\u{1F600}\uDFFF';
      const units = [0x41, 0, 0xd83d, 0xde00, 0xdfff];
      for (final (index, unit) in units.indexed) {
        expect(runner.run(function, [text, index]), unit);
      }
      for (final index in [-1, units.length]) {
        expect(() => runner.run(function, [text, index]), throwsRangeError);
      }
    },
  );
}
