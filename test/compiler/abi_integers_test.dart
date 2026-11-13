@Tags(['assets', 'native'])
library;

import 'dart:ffi';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import 'fixtures/abi_integers.dart' as sdk;
import 'fixtures/abi_integers_ffi.dart';

void main() {
  late AbiIntegers library;
  setUpAll(() {
    library = AbiIntegers();
    addTearDown(library.close);
  });

  test('ABI integers use target widths and signs at call boundaries', () {
    final target = Target.host();
    final (bits, signed) = switch ((
      target.operatingSystem,
      target.architecture,
    )) {
      (.macos, .arm64) => (8, true),
      (.macos, .x64) => (16, true),
      (.linux, .arm64) => (16, false),
      (.linux, .x64) => (32, true),
    };
    int truncate(int value) =>
        signed ? value.toSigned(bits) : value.toUnsigned(bits);
    expect(library.integerSize(), bits ~/ 8);
    expect(library.integerSize(), sizeOf<sdk.PlatformInt>());
    expect(library.stateSize(), sizeOf<sdk.IntegerState>());
    for (final value in [
      -0x80000000,
      -129,
      -1,
      0,
      127,
      255,
      65535,
      0x7fffffff,
    ]) {
      expect(library.identity(value), truncate(value));
      expect(library.invoke(library.callback, value), truncate(value));
      expect(
        library.stack(
          value,
          value,
          value,
          value,
          value,
          value,
          value,
          value,
          value,
          value,
        ),
        truncate(10 * truncate(value)),
      );
      expect(
        library.character(value),
        target == const Target(.linux, .arm64)
            ? value.toUnsigned(8)
            : value.toSigned(8),
      );
    }
  });

  test(
    'typed pointers and struct arrays share layout and preserve neighbours',
    () {
      final bytes = library.memory.cast<Uint8>().asTypedList(64);
      for (final index in [0, 2, 5]) {
        for (final value in [-1, 0x12345678]) {
          bytes.fillRange(0, bytes.length, 0xa5);
          final actual = library.access(library.memory, index, value);
          final written = bytes.toList();
          bytes.fillRange(0, bytes.length, 0xa5);
          expect(actual, sdk.access(library.memory, index, value));
          expect(written, bytes);
          expect(
            library.offset(library.memory, -index),
            sdk.offset(library.memory, -index),
          );
        }
      }
      final state = library.memory.cast<sdk.IntegerState>();
      bytes.fillRange(0, bytes.length, 0xa5);
      final actual = library.update(state, 0x12345678);
      final written = bytes.toList();
      bytes.fillRange(0, bytes.length, 0xa5);
      expect(actual, sdk.update(state, 0x12345678));
      expect(written, bytes);
    },
  );
}
