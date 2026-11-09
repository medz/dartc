@Tags(['assets', 'native'])
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:test/test.dart';

import 'fixtures/pointer_arithmetic.dart' as sdk;
import 'fixtures/pointer_arithmetic_ffi.dart';

void main() {
  late PointerArithmeticLibrary library;
  late Pointer<Int64> memory;
  setUpAll(() {
    library = PointerArithmeticLibrary();
    addTearDown(library.close);
    memory = library.memory;
  });

  test(
    'scalar pointer offsets scale elements and wrap without dereferencing',
    () {
      for (final (name, size, reference) in [
        ('Int8', 1, sdk.offsetInt8),
        ('Uint8', 1, sdk.offsetUint8),
        ('Int16', 2, sdk.offsetInt16),
        ('Uint16', 2, sdk.offsetUint16),
        ('Int32', 4, sdk.offsetInt32),
        ('Uint32', 4, sdk.offsetUint32),
        ('Int64', 8, sdk.offsetInt64),
        ('Uint64', 8, sdk.offsetUint64),
        ('Float', 4, sdk.offsetFloat),
        ('Double', 8, sdk.offsetDouble),
      ]) {
        final offset = library.offset(name);
        for (final address in [0, -1, 0x7fffffffffffffff, memory.address]) {
          for (final index in [
            0,
            1,
            -3,
            -0x8000000000000000,
            0x7fffffffffffffff,
          ]) {
            for (var operation = 0; operation < 3; operation++) {
              final expected =
                  (BigInt.from(address) +
                          BigInt.from(index) *
                              BigInt.from(operation == 1 ? -size : size))
                      .toSigned(64)
                      .toInt();
              expect(offset(address, index, operation), expected, reason: name);
              expect(
                reference(address, index, operation),
                expected,
                reason: name,
              );
            }
          }
        }
      }
    },
  );

  test(
    'integer indexing extends loads and writes only the addressed bytes',
    () {
      final bytes = memory.cast<Uint8>().asTypedList(96);
      for (final (name, size, signed, reference) in [
        ('Int8', 1, true, sdk.indexedInt8),
        ('Uint8', 1, false, sdk.indexedUint8),
        ('Int16', 2, true, sdk.indexedInt16),
        ('Uint16', 2, false, sdk.indexedUint16),
        ('Int32', 4, true, sdk.indexedInt32),
        ('Uint32', 4, false, sdk.indexedUint32),
        ('Int64', 8, true, sdk.indexedInt64),
        ('Uint64', 8, false, sdk.indexedUint64),
      ]) {
        final indexed = library.indexedInteger(name);
        for (final index in [-3, 0, 3]) {
          final start = 32 + index * size;
          for (final value in [0, -1, 0x123456789abcdef, -0x8000000000000000]) {
            final integer = BigInt.from(value);
            final expected =
                (signed
                        ? integer.toSigned(size * 8)
                        : integer.toUnsigned(size * 8))
                    .toSigned(64)
                    .toInt();
            final contents = [
              for (var i = 0; i < bytes.length; i++)
                i >= start && i < start + size
                    ? (value >>> ((i - start) * 8)) & 255
                    : 0xa5,
            ];
            bytes.fillRange(0, bytes.length, 0xa5);
            expect(
              indexed(memory.address + 32, index, value),
              expected,
              reason: name,
            );
            expect(bytes, contents);
            bytes.fillRange(0, bytes.length, 0xa5);
            expect(reference(memory.address + 32, index, value), expected);
            expect(bytes, contents);
          }
        }
      }
    },
  );

  test(
    'floating indexing preserves native precision and neighboring storage',
    () {
      final bytes = memory.cast<Uint8>().asTypedList(96);
      for (final (name, size, reference) in [
        ('Float', 4, sdk.indexedFloat),
        ('Double', 8, sdk.indexedDouble),
      ]) {
        final indexed = library.indexedFloat(name);
        for (final index in [-3, 0, 3]) {
          final start = 32 + index * size;
          for (final value in [-0.0, 1.0 + 1.0 / 16777216, 1e40, double.nan]) {
            final data = ByteData(size);
            if (size == 4) {
              data.setFloat32(0, value, .little);
            } else {
              data.setFloat64(0, value, .little);
            }
            final expected = size == 4 ? data.getFloat32(0, .little) : value;
            for (final call in [indexed, reference]) {
              bytes.fillRange(0, bytes.length, 0xa5);
              final result = call(memory.address + 32, index, value);
              expect(result, expected.isNaN ? isNaN : expected);
              if (value == 0) expect(result.isNegative, value.isNegative);
              expect(bytes.take(start), everyElement(0xa5));
              expect(bytes.skip(start + size), everyElement(0xa5));
              if (!value.isNaN) {
                expect(
                  bytes.sublist(start, start + size),
                  data.buffer.asUint8List(),
                );
              }
            }
          }
        }
      }
    },
  );

  test(
    'indexed updates evaluate receiver, key and right value once in order',
    () {
      for (final alias in [false, true]) {
        final target = memory + (alias ? 0 : 8);
        for (final call in [library.update, sdk.update]) {
          memory.value = 0;
          if (!alias) target.value = 5;
          final result = call(memory, target + 1, -1);
          expect(result, alias ? 133113 : 514);
          expect(target.value, alias ? 131913 : 14);
          expect(memory.value, alias ? 131913 : 1212312);
        }
      }
    },
  );

  test('offset pointers survive calls and loop edge transfers', () {
    for (var i = 0; i < 16; i++) {
      memory[i] = i * 3 - 7;
    }
    for (final count in [0, 1, 8, 16]) {
      final expected = 3 * count * (count - 1) ~/ 2 - 7 * count;
      expect(library.sum(memory, count), expected);
      expect(sdk.sum(memory, count), expected);
    }
  });
}
