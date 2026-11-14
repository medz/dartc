import 'dart:typed_data';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

void main() {
  test('target parsing never substitutes the host', () {
    for (final os in OperatingSystem.values) {
      for (final arch in Architecture.values) {
        final target = Target(os, arch);
        expect(Target.parse(target.toString()), target);
        expect(target.wordSize, 8);
        expect(target.byteOrder, Endian.little);
      }
    }
    expect(() => Target.parse('windows-x64'), throwsFormatException);
  });
}
