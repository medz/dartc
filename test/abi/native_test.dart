@Tags(['assets', 'native'])
library;

import 'package:test/test.dart';

import 'fixtures/frames_ffi.dart';
import 'fixtures/stack_calls_ffi.dart';
import '../compiler/fixtures/stack_helpers.dart' as sdk;

void main() {
  test('preserves double locals and callee-saved scalar lanes', () {
    final frames = FloatingFrames();
    addTearDown(frames.close);
    for (final value in [-1000.0, 0.0, 42.25, double.infinity]) {
      expect(frames.roundTrip(value), value + 3.5);
    }
  });
  test('an independent ABI caller passes stack words into another object', () {
    final arguments = StackArguments();
    addTearDown(arguments.close);
    for (final value in [-0x8000000000000000, -71, 0, 0x7fffffffffffffff]) {
      expect(
        arguments.forward(value, 2, 3, 4, 5, 6, value, 8, value, value),
        sdk.weighted10(value, 2, 3, 4, 5, 6, value, 8, value, value),
      );
    }
  });

  test(
    'preserves local storage and saved registers across a nested native call',
    () {
      final frames = Frames();
      addTearDown(frames.close);
      for (final value in [-1000, 0, 42, 0x7fffffffffffffff]) {
        expect(frames.roundTrip(value), value + 61);
      }
    },
  );
}
