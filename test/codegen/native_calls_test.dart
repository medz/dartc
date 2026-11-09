@Tags(['assets', 'native'])
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:test/test.dart';

import 'fixtures/native_calls_ffi.dart';

void main() {
  for (final indirect in [false, true]) {
    group(indirect ? 'indirect' : 'bound', () {
      late NativeCalls library;
      setUpAll(() {
        library = NativeCalls(indirect: indirect);
        addTearDown(library.close);
      });
      double float32(double value) =>
          (ByteData(4)..setFloat32(0, value, .little)).getFloat32(0, .little);

      test(
        'outgoing integer boundaries convert arguments and dirty result bits',
        () {
          for (final (name, bits, signed) in [
            ('Int8', 8, true),
            ('Uint8', 8, false),
            ('Int16', 16, true),
            ('Uint16', 16, false),
            ('Int32', 32, true),
            ('Uint32', 32, false),
            ('Int64', 64, true),
            ('Uint64', 64, false),
          ]) {
            final argument = library.integer('argument$name');
            final result = library.integer('result$name');
            for (final value in [
              0,
              -1,
              129,
              -129,
              0x123456789abcdef,
              -0x8000000000000000,
              0x7fffffffffffffff,
            ]) {
              final integer = BigInt.from(value);
              final converted =
                  (signed ? integer.toSigned(bits) : integer.toUnsigned(bits))
                      .toSigned(64)
                      .toInt();
              expect(result(value), converted, reason: name);
              expect(argument(value), converted + value, reason: name);
            }
          }
        },
      );

      test('outgoing Float calls preserve live Dart doubles and widen native results', () {
        for (final value in [
          0.0,
          -0.0,
          1.0 + 1.0 / 16777216,
          1e-45,
          1e40,
          double.infinity,
          double.nan,
        ]) {
          final rounded = float32(value);
          final result = library.resultFloat(value);
          expect(result, rounded.isNaN ? isNaN : rounded);
          expect(
            library.argumentFloat(value),
            rounded.isNaN ? isNaN : rounded + value,
          );
          if (value == 0) expect(result.isNegative, value.isNegative);
        }
      });

      test(
        'native pointer results and void calls preserve addresses and writes',
        () {
          final memory = library.memory;
          expect(library.pointer(memory).address, memory.address);
          for (final value in [-1, 0, 0x123456789abcdef]) {
            expect(library.write(memory, value), value);
            expect(memory.value, value);
          }
        },
      );

      test('byte-sized stack arguments can fill the outgoing area exactly', () {
        final packed = library.integer('packed');
        for (final value in [-257, 0, 129, 0x7fffffffffffffff]) {
          final expected = [for (var i = 0; i < 24; i++) (value + i * 17) & 255]
              .fold(0, (sum, element) => sum + element);
          expect(packed(value), expected);
        }
      });

      test('mixed outgoing register and packed stack arguments agree with SDK calls', () {
        final memory = library.memory.cast<Double>()..value = 13.25;
        for (final integer in [-129, 256, 65535]) {
          for (final value in [1.0 + 1.0 / 16777216, -7.125]) {
            final expected =
                <double>[
                  for (var i = 1; i <= 8; i++)
                    i.isOdd ? float32(value + i) : value + i,
                  for (var i = 1; i <= 8; i++) (integer + i).toDouble(),
                  float32(value),
                  float32(value),
                  integer.toSigned(8).toDouble(),
                  value,
                  memory.value,
                ].fold(0.0, (sum, value) => sum + value) +
                value;
            expect(library.mixed(memory, integer, value), expected);
            expect(
              library.providedMixed(
                    value + 1,
                    value + 2,
                    value + 3,
                    value + 4,
                    value + 5,
                    value + 6,
                    value + 7,
                    value + 8,
                    integer + 1,
                    integer + 2,
                    integer + 3,
                    integer + 4,
                    integer + 5,
                    integer + 6,
                    integer + 7,
                    integer + 8,
                    value,
                    value,
                    integer,
                    value,
                    memory,
                  ) +
                  value,
              expected,
            );
          }
        }
      });
    });
  }

  test(
    'stack-resident function pointers survive selection, loops and clobbers',
    () {
      final library = NativeCalls();
      addTearDown(library.close);
      for (final choose in [0, 1]) {
        for (final value in [-1, 129, 0x123456789abcdef]) {
          expect(
            library.repeated(
              choose,
              value,
              7,
              0,
              0,
              0,
              0,
              0,
              choose == 0 ? library.identity : nullptr,
              choose == 1 ? library.identity : nullptr,
            ),
            value * 7,
          );
        }
      }
      expect(library.repeated(0, 42, 0, 0, 0, 0, 0, 0, nullptr, nullptr), 0);
    },
  );
}
