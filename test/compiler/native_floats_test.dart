@Tags(['assets', 'native'])
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:dartc/frontend.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';
import 'fixtures/native_floats.dart' as sdk;
import 'fixtures/native_floats_ffi.dart';

void sameDouble(double actual, double expected) {
  expect(actual, expected.isNaN ? isNaN : expected);
  if (expected == 0) expect(actual.isNegative, expected.isNegative);
}

double floatBits(int bits) => (ByteData(4)..setUint32(0, bits)).getFloat32(0);

void main() {
  late NativeFloats native;
  setUpAll(() {
    native = NativeFloats();
    addTearDown(native.close);
  });
  // Binary32 round-to-nearest, ties-to-even boundaries, including subnormals.
  const rounding = [
    (0.0, 0x00000000),
    (-0.0, 0x80000000),
    (1.0000000596046448, 0x3f800000),
    (1.0000001788139343, 0x3f800002),
    (-1.0000000596046448, 0xbf800000),
    (16777217.0, 0x4b800000),
    (16777219.0, 0x4b800002),
    (7.006492321624085e-46, 0x00000000),
    (-7.006492321624085e-46, 0x80000000),
    (1.401298464324817e-45, 0x00000001),
    (2.1019476964872256e-45, 0x00000002),
    (1.1754943508222875e-38, 0x00800000),
    (3.4028234663852886e38, 0x7f7fffff),
    (1e39, 0x7f800000),
    (-1e39, 0xff800000),
    (double.infinity, 0x7f800000),
    (double.negativeInfinity, 0xff800000),
    (double.nan, 0x7fc00000),
  ];

  test(
    'FFI converts float precision without narrowing ordinary Dart calls',
    () {
      for (final (value, bits) in rounding) {
        final expected = floatBits(bits);
        sameDouble(native.identity(value), expected);
        sameDouble(native.widen(value), expected);
        sameDouble(native.narrow(value), expected);
        sameDouble(native.internal(value), sdk.internal(value));
      }
    },
  );

  test(
    'floating memory preserves neighboring bytes and live double values',
    () async {
      final lowered = await AnalysisSession([
        'test/compiler/fixtures/native_floats.dart',
      ]).use(Lowering().lower);
      final interpreter = IrInterpreter(lowered.program, {});
      double interpret(String name, List<Object?> args) => interpreter.run(
        lowered.program.functions.singleWhere((f) => f.target.name == name),
        args,
      ) as double;
      final bytes = native.memory.asTypedList(24);
      final first = native.fromFloatAddress(native.memory.address + 8);
      final second = native.fromDoubleAddress(native.memory.address + 8);
      expect(first.address, native.memory.address + 8);
      expect(second.address, first.address);
      for (final (value, bits) in rounding) {
        bytes.fillRange(0, bytes.length, 0xa5);
        final expected = floatBits(bits);
        sameDouble(native.writeFloat(first, value), value);
        sameDouble(native.readFloat(first), expected);
        sameDouble(interpret('readFloat', [first]), expected);
        sameDouble(interpret('writeFloat', [first, value]), value);
        sameDouble(first.value, expected);
        expect(bytes.take(8), everyElement(0xa5));
        expect(bytes.skip(12), everyElement(0xa5));
        if (!value.isNaN) {
          expect(bytes.skip(8).take(4), [
            for (var i = 0; i < 4; i++) (bits >>> (i * 8)) & 255,
          ]);
        }

        bytes.fillRange(0, bytes.length, 0xa5);
        sameDouble(native.writeDouble(second, value), value);
        sameDouble(native.readDouble(second), value);
        sameDouble(interpret('writeDouble', [second, value]), value);
        sameDouble(interpret('readDouble', [second]), value);
        expect(bytes.take(8), everyElement(0xa5));
        expect(bytes.skip(16), everyElement(0xa5));
      }
    },
  );

  test('compound writes return Dart values and keep alias ordering', () {
    final pointer = native.memory.cast<Float>();
    for (final value in [1.0000000596046448, 16777217.0, -1.5]) {
      pointer.value = 0;
      final expected = sdk.update(pointer, value), stored = pointer.value;
      pointer.value = 0;
      sameDouble(native.update(pointer, value), expected);
      sameDouble(pointer.value, stored);
      final old = sdk.postIncrement(pointer), incremented = pointer.value;
      pointer.value = stored;
      sameDouble(native.postIncrement(pointer), old);
      sameDouble(pointer.value, incremented);
      sameDouble(
        native.alias(pointer, pointer, value),
        sdk.alias(pointer, pointer, value),
      );
    }
  });

  test('float and double arguments survive packed and word stack layouts', () {
    final pointer = native.memory.cast<Double>()..value = 0.125;
    double call(sdk.MixedDart function, bool nativeBoundary) {
      double argument(double value) => nativeBoundary
          ? value
          : (ByteData(4)..setFloat32(0, value)).getFloat32(0);
      return function(
        argument(1.0000000596046448),
        2.25,
        argument(3.0000001),
        4.5,
        argument(5.0000001),
        6.75,
        argument(7.0000001),
        8.25,
        1,
        -2,
        3,
        -4,
        5,
        -6,
        7,
        -8,
        argument(16777217.0),
        argument(-16777219.0),
        -127,
        10.5,
        pointer,
      );
    }

    sameDouble(call(native.mixed, true), call(sdk.mixed, false));
  });
}
