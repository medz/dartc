import 'dart:typed_data';

import 'package:dartc/layout.dart';
import 'package:test/test.dart';

void main() {
  test('stack records retain linkage and incoming argument roots', () {
    final offsets = [8, 24, 80];
    final roots = StackRoots(64, 56, offsets);
    offsets.clear();
    final data = ByteData(roots.size + 8);
    roots.writeTo(data, 8);
    final read = StackRoots.read(data, 8);
    expect(read.callerStackOffset, 64);
    expect(read.returnAddressOffset, 56);
    expect(read.offsets, [8, 24, 80]);
    expect(() => read.offsets.clear(), throwsUnsupportedError);
    expect(StackRoots(0, 0, []).size, 24);
  });

  test('stack records reject invalid linkage, slots and truncated data', () {
    for (final (caller, address, slots) in [
      (-8, 0, <int>[]),
      (16, 16, <int>[]),
      (0, 8, <int>[]),
      (16, 8, [1]),
      (16, 8, [-8]),
      (16, 8, [8]),
      (16, 8, [0, 0]),
      (32, 24, [16, 0]),
    ]) {
      expect(() => StackRoots(caller, address, slots), throwsArgumentError);
    }
    expect(() => StackRoots.read(ByteData(23), 0), throwsRangeError);
    final data = ByteData(24)..setUint64(16, 1, .little);
    expect(() => StackRoots.read(data, 0), throwsFormatException);
    expect(() => StackRoots(0, 0, []).writeTo(data, 8), throwsRangeError);
  });
}
