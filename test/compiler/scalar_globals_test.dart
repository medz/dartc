@Tags(['assets', 'native'])
library;

import 'dart:typed_data';

import 'package:test/test.dart';

import 'fixtures/scalar_globals_ffi.dart';

void main() {
  late ScalarGlobals native;
  setUpAll(() {
    native = ScalarGlobals();
    addTearDown(native.close);
  });

  test(
    'integer and boolean writes persist across different native exports',
    () {
      expect(native.writeCounter(9007199254740993), 9007199254740993);
      expect(native.readCounter(), 9007199254740993);
      expect(native.addCounter(7), 9007199254741000);
      expect(native.readCounter(), 9007199254741000);
      expect(native.writeCounter(0), 0);
      expect(native.readCounter(), 0);
      expect(native.writeFlag(0), 0);
      expect(native.toggleFlag(), 1);
      expect(native.toggleFlag(), 0);
      expect(native.writeFlag(7), 1);
      expect(native.toggleFlag(), 0);
    },
  );

  test('double storage preserves signed zero, infinity and NaN payloads', () {
    int bits(double value) => (ByteData(8)..setFloat64(0, value)).getUint64(0);
    double fromBits(int value) =>
        (ByteData(8)..setUint64(0, value)).getFloat64(0);
    expect(bits(native.readFloating()), bits(-0.0));
    for (final value in [
      0.0,
      -0.0,
      1.25,
      double.infinity,
      double.negativeInfinity,
      fromBits(0x7ff8000000000042),
      fromBits(0xfff8000000000042),
    ]) {
      expect(bits(native.writeFloating(value)), bits(value));
      expect(bits(native.readFloating()), bits(value));
      expect(bits(native.readFloating()), bits(value));
    }
  });

  test('class declarations own distinct slots shared by generic instances', () {
    expect(native.classState(1, 0), 11);
    expect(native.classState(3, 0), 22);
    expect(native.writeCounter(3), 3);
    expect(native.classState(0, 41), 41);
    expect(native.classState(2, 52), 52);
    expect(native.classState(1, 0), 41);
    expect(native.classState(3, 0), 52);
    expect(native.readCounter(), 3);
  });

  test(
    'successful lazy initialization runs once and pre-read writes skip it',
    () {
      expect(native.lazyState(1), 0);
      expect(native.lazyState(0), 42);
      expect(native.lazyState(0), 42);
      expect(native.lazyState(1), 1);
      expect(native.skippedState(2, 0), 0);
      expect(native.skippedState(0, 0), 0);
      expect(native.skippedState(1, 0), 0);
      expect(native.skippedState(2, 0), 0);
    },
  );

  test(
    'failed initialization retries without rolling back a committed write',
    () {
      expect(native.retryState(1), 0);
      expect(native.retryState(0), -1);
      expect(native.retryState(1), 1);
      expect(native.retryState(0), 72);
      expect(native.retryState(0), 72);
      expect(native.retryState(1), 2);
      expect(native.writtenState(1), 0);
      expect(native.writtenState(0), -1);
      expect(native.writtenState(0), 91);
      expect(native.writtenState(0), 91);
      expect(native.writtenState(1), 1);
    },
  );

  test('finite recursive initialization commits the outer result last', () {
    expect(native.recursiveState(1), 0);
    // Inner write 7 becomes inner result 20, then outer result 30.
    expect(native.recursiveState(0), 30);
    expect(native.recursiveState(0), 30);
    expect(native.recursiveState(1), 2);
  });

  test(
    'allocating initializer preserves live references and binds its scalar',
    () {
      expect(native.allocatedState(1), 0);
      expect(native.allocatedState(0), 40041);
      expect(native.allocatedState(0), 40041);
      expect(native.allocatedState(1), 1);
    },
  );

  test('late scalar reads fail until binding and final writes bind once', () {
    expect(
      [
        for (final mode in [0, 1, 2, 0, 4, 6]) native.lateState(mode),
      ],
      [-1, -1, -1, -1, -1, -1],
    );
    expect(
      [
        for (final mode in [3, 0, 1, 2, 5, 4, 8, 4, 7, 6, 7, 6])
          native.lateState(mode),
      ],
      [3, 0, 1, 0, 5, 1, -1, 1, 7, 1, -1, 1],
    );
    // Wrong-typed and throwing RHS expressions win over a bound-final error.
    expect(
      [
        for (final mode in [0, 1, 2, 3, 4, 5]) native.finalWriteState(mode),
      ],
      [42, -1, -2, -3, 42, 4],
    );
  });

  test(
    'recursive final initialization preserves the inner binding on failure',
    () {
      expect(
        [
          for (final mode in [1, 0, 0, 1, 3, 2, 2, 3, 5, 4, 4, 5])
            native.finalRecursiveState(mode),
        ],
        [0, -1, 20, 2, 0, -1, 30, 2, 0, -2, 40, 2],
      );
    },
  );

  test('late errors and captured traces survive allocating cleanup', () {
    expect(native.lateErrorCleanup(40000), 1234);
    // Failure never binds the slot, even across exported activations.
    expect(native.lateErrorCleanup(1), 1234);
  });
}
