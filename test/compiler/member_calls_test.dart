@Tags(['assets', 'native'])
library;

import 'package:test/test.dart';

import 'fixtures/member_calls.dart' as sdk;
import 'fixtures/member_calls_ffi.dart';

void main() {
  test(
    'member entries preserve defaults, covariance, bounds, results and cleanup',
    () {
      final native = MemberCalls();
      addTearDown(native.close);
      for (final count in [0, 10000]) {
        for (final word in [-0x8000000000000000, 0x7fffffffffffffff]) {
          for (final number in [-0.0, double.nan]) {
            for (var mode = 0; mode < 7; mode++) {
              final expected = sdk.memberCalls(mode, word, number, count);
              if (mode < 3) expect(expected, word * 2 + [191, 415, 639][mode]);
              if (mode >= 3) expect(expected, [63, 3, 7, 1][mode - 3]);
              expect(
                native.call(mode, word, number, count),
                expected,
                reason: '$mode, $word, $number, $count',
              );
            }
          }
        }
      }
    },
  );
}
