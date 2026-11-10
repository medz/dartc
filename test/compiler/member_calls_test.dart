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
        for (var mode = 0; mode < 7; mode++) {
          for (final word
              in mode < 5 ? [-0x8000000000000000, 0x7fffffffffffffff] : [0]) {
            for (final number
                in mode == 3 || mode == 4 ? [-0.0, double.nan] : [0.0]) {
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
