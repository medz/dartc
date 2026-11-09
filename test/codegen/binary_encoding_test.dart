import 'package:dartc/src/codegen/binary_encoding.dart';
import 'package:test/test.dart';

void main() {
  test('rejects an unsatisfied destructive operand before emission', () {
    final operands = <(int, int, int)>[];
    final encoding = BinaryEncoding<int>(
      (destination, left, right) => operands.add((destination, left, right)),
      reuseLeft: true,
    );
    expect(() => encoding.emit(2, 0, 1), throwsStateError);
    expect(operands, isEmpty);
    encoding.emit(0, 0, 1);
    encoding.emit(0, 0, 0);
    expect(operands, [(0, 0, 1), (0, 0, 0)]);
  });
}
