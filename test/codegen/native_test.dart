import 'package:test/test.dart';

import 'fixtures/aliases_ffi.dart';

void main() {
  final native = Aliases();
  tearDownAll(native.close);

  test('arithmetic preserves aliased right operands', () {
    expect(native.add(40, 2), 42);
    expect(native.subtract(40, 2), 38);
    expect(native.subtract(2, 40), -38);
  });
}
