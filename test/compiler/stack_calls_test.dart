@Tags(['assets', 'native'])
library;

import 'package:test/test.dart';

import 'fixtures/stack_calls.dart' as sdk;
import 'fixtures/stack_helpers.dart' as helper;
import 'fixtures/stack_calls_ffi.dart';

void main() {
  int invoke(TenDart function, List<int> values) => function(
    values[0],
    values[1],
    values[2],
    values[3],
    values[4],
    values[5],
    values[6],
    values[7],
    values[8],
    values[9],
  );

  test(
    'register and stack arguments retain order, lifetime and all 64 bits',
    () {
      final native = StackCalls();
      addTearDown(native.close);
      final values = List.generate(10, (i) => i + 1);
      for (final boundary in [
        -0x8000000000000000,
        -37,
        0,
        0x7fffffffffffffff,
      ]) {
        for (var position = 0; position < values.length; position++) {
          final input = [...values]..[position] = boundary;
          for (final (name, actual, expected) in <(String, TenDart, TenDart)>[
            ('weighted', native.weighted, helper.weighted10),
            ('last', native.last, sdk.last10),
            ('forward', native.forward, sdk.forward10),
            ('rotate', native.rotate, sdk.rotate10),
          ]) {
            expect(
              invoke(actual, input),
              invoke(expected, input),
              reason: '$name $input',
            );
          }
        }
      }
    },
  );
}
