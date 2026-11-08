import 'package:test/test.dart';

import 'fixtures/arithmetic.dart' as sdk;
import 'fixtures/arithmetic_ffi.dart';

void main() {
  final native = Arithmetic();
  tearDownAll(native.close);

  test(
    'native functions accept arguments and return values through Dart FFI',
    () {
      expect(native.add(19, 23), 42);
      expect(native.reverse(10, 3), -7);
      expect(native.twice(-21), -42);
      expect(native.literal(), 0x123456789abcdef0);
      expect(native.mixed(100, 2, 30, 4, 5, 7), 122);
    },
  );

  test('native arithmetic agrees with the SDK at integer boundaries', () {
    const values = [-0x8000000000000000, -1, 0, 42, 0x7fffffffffffffff];
    for (final a in values) {
      expect(native.twice(a), sdk.twice(a));
      expect(native.increment(a), sdk.increment(a));
      for (final b in values) {
        expect(native.add(a, b), sdk.add(a, b));
        expect(native.reverse(a, b), sdk.reverse(a, b));
      }
    }
  });
}
