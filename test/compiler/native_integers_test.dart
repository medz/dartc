@Tags(['assets', 'native'])
library;

import 'dart:ffi';

import 'package:dartc/frontend.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';
import 'fixtures/native_integers.dart' as sdk;
import 'fixtures/native_integers_ffi.dart';

void main() {
  late NativeIntegers library;
  setUpAll(() {
    library = NativeIntegers();
    addTearDown(library.close);
  });
  const types = [
    'Int8',
    'Uint8',
    'Int16',
    'Uint16',
    'Int32',
    'Uint32',
    'Int64',
    'Uint64',
  ];
  const values = [
    0,
    -1,
    127,
    128,
    255,
    256,
    32767,
    32768,
    65535,
    65536,
    0x7fffffff,
    0x80000000,
    0xffffffff,
    0x100000000,
    -0x8000000000000000,
    0x7fffffffffffffff,
  ];

  test('native integer accesses truncate only the addressed bytes', () async {
    final program = await AnalysisSession([
      'test/compiler/fixtures/native_integers.dart',
    ]).use(Lowering().lower);
    final interpreter = IrInterpreter(program.program, {});
    final storage = library.memory.asTypedList(24);
    for (final (i, name) in types.indexed) {
      final bytes = 1 << (i ~/ 2), signed = i.isEven;
      final access = library.accesses[i];
      final read = program.program.functions.singleWhere(
        (f) => f.target.name == 'read$name',
      );
      final write = program.program.functions.singleWhere(
        (f) => f.target.name == 'write$name',
      );
      for (final value in values) {
        final expected = signed
            ? value.toSigned(bytes * 8)
            : value.toUnsigned(bytes * 8);
        storage.fillRange(0, storage.length, 0xa5);
        expect(access.write(library.memory.address + 8, value), expected);
        expect(access.read(library.memory.address + 8), expected);
        expect(interpreter.run(read, [library.memory.address + 8]), expected);
        expect(
          interpreter.run(write, [library.memory.address + 8, value]),
          expected,
        );
        expect(storage.take(8), everyElement(0xa5));
        expect(storage.skip(8 + bytes), everyElement(0xa5));
        expect(storage.skip(8).take(bytes), [
          for (var b = 0; b < bytes; b++) (value >>> (b * 8)) & 255,
        ]);
      }
    }
  });

  test('native parameters and results use signed or unsigned extension', () {
    for (final (i, conversion) in library.conversions.indexed) {
      final bits = 8 << (i ~/ 2), signed = i.isEven;
      for (final value in values) {
        final expected = signed ? value.toSigned(bits) : value.toUnsigned(bits);
        expect(conversion.extend(value), expected);
        expect(conversion.truncate(value), expected);
      }
    }
    for (final value in values) {
      expect(library.unsigned64(value), value);
      expect(library.internal(value), sdk.internal(value));
    }
  });

  test(
    'native pointer identities and compound writes preserve element widths',
    () {
      final first = library.fromAddress(library.memory.address + 8);
      final second = (library.memory + 2).cast<Int8>();
      expect(
        first.address,
        sdk.fromAddress(library.memory.address + 8).address,
      );
      for (final value in [1, -1, 65535, 65536]) {
        first.value = 65535;
        second.value = 127;
        final expected = sdk.update(first, second, value);
        final stored = (first.value, second.value);
        first.value = 65535;
        second.value = 127;
        expect(library.update(first, second, value), expected);
        expect((first.value, second.value), stored);
      }
    },
  );

  test(
    'mixed narrow integers and doubles respect packed and word stack layouts',
    () {
      final pointer = library.memory.cast<Uint16>()..value = 500;
      double call(sdk.MixedDart function) => function(
        -127,
        255,
        -32768,
        65535,
        -2147483648,
        4294967295,
        17,
        22,
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        -5,
        65534,
        9.5,
        -2147483647,
        pointer,
      );
      expect(call(library.mixed), call(sdk.mixed));
    },
  );
}
