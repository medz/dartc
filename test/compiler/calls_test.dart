import 'package:test/test.dart';

import 'fixtures/calls.dart' as sdk;
import 'fixtures/calls_ffi.dart';

void main() {
  final native = Calls();
  tearDownAll(native.close);

  test(
    'cross-file calls preserve arguments, live values and frame records',
    () {
      const values = [-0x8000000000000000, -123, -1, 0, 42, 0x7fffffffffffffff];
      expect(native.literalCall(), sdk.literalCall());
      for (final a in values) {
        expect(native.repeated(a), sdk.repeated(a));
        expect(native.unusedCall(a), sdk.unusedCall(a));
        expect(native.pressure(a), sdk.pressure(a));
        for (final b in values) {
          expect(native.calls(a, b), sdk.calls(a, b), reason: '$a, $b');
        }
      }
    },
  );

  test('only annotated definitions are exported', () {
    expect(native.hasSymbol('calls'), isTrue);
    for (final name in ['subtract', 'add', 'twice', 'offset', '_difference']) {
      expect(native.hasSymbol(name), isFalse, reason: name);
    }
  });
}
