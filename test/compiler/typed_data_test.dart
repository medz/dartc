@Tags(['assets', 'native'])
library;

import 'package:test/test.dart';

import 'fixtures/typed_data.dart';
import 'fixtures/typed_data_ffi.dart';

void main() {
  late NativeTypedData native;
  setUpAll(() {
    native = NativeTypedData();
    addTearDown(native.close);
  });
  test(
    'scalar typed lists preserve widths, signedness and float precision',
    () {
      for (final seed in [-129, 0, 127, 256, 0x80000000]) {
        final actual = native.lists(seed, 1.23456789);
        final expected = typedLists(seed, 1.23456789);
        expect(actual.integers, expected.integers);
        expect(actual.floating, expected.floating);
        expect(actual.bits, -1);
        expect(actual.length, 8);
      }
    },
  );
  test('ByteData preserves endian, unaligned accesses and view offsets', () {
    for (final value in [0.0, -0.0, 1.23456789, -42.5, 1.0e-30]) {
      final actual = native.bytes(value), expected = byteViews(value);
      expect(actual.integers, -0x1234);
      expect(actual.floating, expected.floating);
      expect(actual.bits, expected.bits);
      expect(actual.length, 22);
      expect(actual.immutable, isTrue);
    }
  });
  test('overlapping views, independent copies and read-only buffers', () {
    expect(native.overlap(), 123446);
    expect(native.overlap(), overlappingTypedViews());
    expect(native.readonly(), 279);
    expect(native.readonly(), readonlyTypedViews());
  });
  test('sizes, alignment and bounds fail before accessing storage', () {
    for (var mode = 0; mode < 11; mode++) {
      expect(native.bounds(mode), isTrue, reason: 'case $mode');
    }
  });
  test('native compounds and inline arrays share typed storage through GC', () {
    for (final value in [-32769, 0, 32767, 65535]) {
      final actual = native.shared(value), expected = sharedNativeViews(value);
      expect(actual.integers, expected.integers);
      expect(actual.floating, -7.0);
      expect(actual.bits, 0x55aa);
      expect(actual.length, 4);
      expect(actual.immutable, isTrue);
    }
  });
  test(
    'typed concatenation, aliased conversions and floating bit patterns',
    () {
      for (var mode = 0; mode < 9; mode++) {
        expect(native.collections(mode), isTrue, reason: 'case $mode');
      }
    },
  );
}
