@Tags(['assets', 'native'])
library;

import 'package:test/test.dart';

import 'fixtures/boolean_text.dart' as sdk;
import 'fixtures/boolean_text_ffi.dart';

void main() {
  test('SDK boolean parsing preserves ASCII case, defaults and failures', () {
    final native = BooleanText();
    addTearDown(native.close);
    for (final source in [
      'true',
      'false',
      'TRUE',
      'FALSE',
      'tRuE',
      'FaLsE',
      '',
      '0',
      '1',
      ' true',
      'false ',
      'trúe',
      'falſe',
      'true\u0000',
      'tru\ud800',
    ]) {
      for (final caseSensitive in [true, false]) {
        for (var mode = 0; mode < 6; mode++) {
          (int, bool?) expected;
          try {
            final value = sdk.parse(source, caseSensitive, mode);
            expected = (value == null ? 1 : 0, value);
          } on FormatException {
            expected = (2, null);
          }
          expect(
            native.parse(source, caseSensitive, mode),
            expected,
            reason: '$source/$caseSensitive/$mode',
          );
        }
      }
    }
  });
}
