import 'package:dartc/src/image/bytes.dart';
import 'package:test/test.dart';

void main() {
  test('integers follow the byte order', () {
    void write(ByteWriter out) => out
      ..u8(1)
      ..u32(0x01020304)
      ..u64(0x0102030405060708);
    final little = ByteWriter(.little), big = ByteWriter(.big);
    write(little);
    write(big);
    expect(little.finish(), [1, 4, 3, 2, 1, 8, 7, 6, 5, 4, 3, 2, 1]);
    expect(big.finish(), [1, 1, 2, 3, 4, 1, 2, 3, 4, 5, 6, 7, 8]);
  });

  test('text and padding fill exact sizes', () {
    final out = ByteWriter(.little)
      ..text('ab', 2)
      ..text('c', 3)
      ..align(4)
      ..align(4)
      ..bytes([9]);
    expect(out.length, 9);
    expect(out.finish(), [97, 98, 99, 0, 0, 0, 0, 0, 9]);
    expect(() => ByteWriter(.little).text('abc', 2), throwsArgumentError);
  });
}
