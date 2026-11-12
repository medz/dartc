import 'package:dartc/ir.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

void main() {
  test(
    'floating bit casts preserve bits and distinguish precision conversion',
    () {
      for (final (width, bits, number) in [
        (64, 0x3ff0000000000000, 1.0),
        (64, -0x8000000000000000, -0.0),
        (32, 0x3f800000, 1.0),
        (32, 0x80000000, -0.0),
      ]) {
        final target = FunctionTarget(null, 'roundTrip', .integer, [.integer]);
        final block = Block(target.parameterTypes);
        final floating = block.emit(
          FloatBitCast(block.parameters.single, width: width),
        );
        final encoded = block.emit(FloatBitCast(floating, width: width));
        block.finish(Return(encoded));
        final body = IrFunction(target, [block]);
        expect(
          IrInterpreter(IrProgram([], [body]), {}).run(body, [bits]),
          bits,
        );
        expect(floating.type, ValueType.floating);
        expect(
          FloatBitCast(Constant.floating(number), width: width).effects,
          isEmpty,
        );
      }
    },
  );
  test('invalid bit widths and non-numeric operands are rejected', () {
    expect(
      () => FloatBitCast(const Constant.integer(0), width: 16),
      throwsArgumentError,
    );
    expect(
      () => FloatBitCast(const Constant.boolean(false)),
      throwsArgumentError,
    );
  });
}
