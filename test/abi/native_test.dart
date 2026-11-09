import 'package:test/test.dart';

import 'fixtures/frames_ffi.dart';

void main() {
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
