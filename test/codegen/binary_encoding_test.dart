import 'package:dartc/src/codegen/binary_encoding.dart';
import 'package:test/test.dart';

void main() {
  test('rejects wrong fixed operands before emission', () {
    for (final fixed in [
      (left: 0, right: 0, result: 0, clobbered: <int>{}),
      (left: 0, right: 1, result: 2, clobbered: <int>{}),
    ]) {
      expect(
        () => BinaryEncoding<int>((_, _, _) {}, fixed: fixed, reuseLeft: true),
        throwsArgumentError,
      );
    }
    var emitted = false;
    final encoding = BinaryEncoding<int>(
      (_, _, _) => emitted = true,
      fixed: (left: 0, right: 1, result: 0, clobbered: {2}),
    );
    for (final (result, left, right) in [(2, 0, 1), (0, 2, 1), (0, 0, 2)]) {
      expect(() => encoding.emit(result, left, right), throwsStateError);
    }
    expect(emitted, isFalse);
    encoding.emit(0, 0, 1);
    expect(emitted, isTrue);
  });

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
