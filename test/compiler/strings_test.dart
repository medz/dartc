@Tags(['assets', 'native'])
library;

import 'dart:ffi';

import 'package:test/test.dart';

import 'fixtures/strings.dart' as sdk;
import 'fixtures/strings_ffi.dart';

void main() {
  late Strings native;
  setUpAll(() {
    native = Strings();
    addTearDown(native.close);
  });

  const units = <List<int>>[
    [],
    [0x44, 0x61, 0x72, 0x74],
    [0x41, 0, 0xd83d, 0xde00, 0x5a],
    [0xd800, 0xdc00, 0xdfff],
  ];
  test('SDK code-unit views retain their string and reject mutation', () {
    for (final (mode, expected) in [
      (0, 65),
      (1, 65),
      (2, 65),
      (3, 65),
      (4, 3),
      (5, 112254),
      (6, 2),
      (7, 2),
    ]) {
      final count = mode == 5 ? 40000 : 0;
      expect(sdk.stringUnitsState(mode, count), expected);
      expect(native.unitsState(mode, count), expected);
      expect(native.savedUnit(0), 65);
      expect(native.savedUnit(2), 0xde00);
    }
  });

  test(
    'character construction checks ranges and consumes its iterator once',
    () {
      for (final (start, end, failure, expected) in [
        (0, -1, 0, 1232326),
        (1, -1, 0, 122326),
        (0, 1, 0, 1236),
        (2, 2, 0, 6),
        (4, -1, 0, 12226),
        (-1, -1, 0, 56),
        (2, 1, 0, 56),
        (0, -1, 1, 123246),
        (0, -1, 2, 1232346),
        (0, -1, 3, 123246),
        (0, -1, 4, 12323256),
      ]) {
        expect(sdk.stringCodesProtocol(start, end, failure), expected);
        expect(native.codesProtocol(start, end, failure), expected);
      }
    },
  );

  test(
    'FFI character input produces bounded UTF-16 output owned by the caller',
    () {
      final system = DynamicLibrary.process();
      final allocate = system
          .lookupFunction<
            Pointer<Void> Function(IntPtr),
            Pointer<Void> Function(int)
          >('malloc');
      final free = system
          .lookupFunction<
            Void Function(Pointer<Void>),
            void Function(Pointer<Void>)
          >('free');
      final memory = allocate(40000 * 12 + 8);
      if (memory.address == 0) {
        throw StateError('Test buffer allocation failed');
      }
      try {
        final input = memory.cast<Int64>();
        final output = (memory.cast<Uint8>() + 40000 * 8).cast<Uint16>();
        final source = input.asTypedList(6);
        source.setAll(0, [0x41, 0, 0x1f600, 0xd800, 0xdfff, 0x10ffff]);
        final storage = output.asTypedList(10);
        for (final convert in [sdk.encodeCharacters, native.encode]) {
          for (final (start, end, expected) in <(int, int, List<int>)>[
            (0, -1, [0x41, 0, 0xd83d, 0xde00, 0xd800, 0xdfff, 0xdbff, 0xdfff]),
            (1, 4, [0, 0xd83d, 0xde00, 0xd800]),
            (3, 3, []),
            (5, 99, [0xdbff, 0xdfff]),
            (99, 100, []),
          ]) {
            storage.fillRange(0, storage.length, 0xdead);
            expect(
              convert(input, 6, start, end, output + 1, 8),
              expected.length,
            );
            expect(
              storage.skip(1).take(expected.length),
              orderedEquals(expected),
            );
            expect(storage.first, 0xdead);
            expect(storage.skip(expected.length + 1), everyElement(0xdead));
          }
          for (final (start, end) in [(-1, -1), (2, 1), (0, -2)]) {
            storage.fillRange(0, storage.length, 0xdead);
            expect(convert(input, 6, start, end, output + 1, 8), -2);
            expect(storage, everyElement(0xdead));
          }
          expect(convert(input, 6, 0, -1, output + 1, 7), -18);
          expect(storage, everyElement(0xdead));
          for (final invalid in [
            -0x8000000000000000,
            -1,
            0x110000,
            0x7fffffffffffffff,
          ]) {
            source[0] = invalid;
            expect(convert(input, 6, 0, -1, output + 1, 8), -2);
            expect(storage, everyElement(0xdead));
          }
          source[0] = 0x41;
        }
        input.asTypedList(40000).fillRange(0, 40000, 0x1f600);
        final large = output.asTypedList(80002)..fillRange(0, 80002, 0xdead);
        expect(native.encode(input, 40000, 0, -1, output + 1, 80000), 80000);
        expect(large.first, 0xdead);
        expect(large.last, 0xdead);
        expect(
          large.skip(1).take(80000),
          orderedEquals([
            for (var i = 0; i < 40000; i++) ...[0xd83d, 0xde00],
          ]),
        );
      } finally {
        free(memory);
      }
      expect(native.unitsState(5, 40000), 112254);
      expect(native.saved(79999), 80000 * 0x10000 + 0xde00);
    },
  );

  test(
    'UTF-16 length and units survive calls, method values and collection',
    () {
      expect(native.length(-1), -1);
      for (final (kind, expected) in units.indexed) {
        expect(sdk.stringLength(kind), expected.length);
        expect(native.length(kind), expected.length);
        for (final (index, value) in expected.indexed) {
          expect(sdk.stringCodeUnits(kind, index), value);
          expect(native.codeUnits(kind, index), value);
          for (final mode in [0, 1, 2, 3]) {
            expect(sdk.stringRead(kind, index, mode, 0), value);
            expect(native.read(kind, index, mode, 40000), value);
          }
        }
      }
    },
  );

  test('invalid code-unit reads preserve RangeError and evaluation order', () {
    for (final (kind, expected) in units.indexed) {
      for (final index in [
        -0x8000000000000000,
        -1,
        expected.length,
        0x7fffffffffffffff,
      ]) {
        for (final bound in [0, 1, 2]) {
          expect(sdk.stringFailure(kind, index, bound), 1234);
          expect(native.failure(kind, index, bound), 1234);
        }
      }
    }
  });

  test('constructed strings preserve Unicode, indexing and value equality', () {
    for (final (code, units) in [
      (0, [0]),
      (0x61, [0x61]),
      (0xffff, [0xffff]),
      (0xd800, [0xd800]),
      (0xdfff, [0xdfff]),
      (0x10000, [0xd800, 0xdc00]),
      (0x1f600, [0xd83d, 0xde00]),
      (0x10ffff, [0xdbff, 0xdfff]),
    ]) {
      for (final (index, unit) in units.indexed) {
        for (final bound in [0, 1]) {
          final expected = units.length * 0x10000 + unit;
          expect(sdk.stringConstruct(code, index, bound), expected);
          expect(native.construct(code, index, bound), expected);
        }
      }
    }
  });

  test(
    'variable payloads survive growth, copying, globals and bound receivers',
    () {
      for (final (code, width, first, last) in [
        (0x61, 1, 0x61, 0x61),
        (0x1f600, 2, 0xd83d, 0xde00),
      ]) {
        for (final rounds in [0, 3, 16]) {
          final expected =
              (width << rounds) * 0x100000000 + first * 0x10000 + last;
          expect(sdk.stringGrowth(code, rounds, 20000), expected);
          expect(native.growth(code, rounds, 20000), expected);
          expect(
            native.saved((width << rounds) - 1),
            (width << rounds) * 0x10000 + last,
          );
        }
      }
    },
  );

  test(
    'invalid character codes throw before unused results can be removed',
    () {
      for (final code in [
        -0x8000000000000000,
        -1,
        0x110000,
        0x7fffffffffffffff,
      ]) {
        for (final bound in [0, 1]) {
          expect(sdk.stringInvalidCode(code, bound), 234);
          expect(native.invalidCode(code, bound), 234);
        }
      }
    },
  );
}
