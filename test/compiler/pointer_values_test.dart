@Tags(['assets', 'native'])
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';
import 'fixtures/pointer_values.dart' as sdk;
import 'fixtures/pointer_values_ffi.dart';

void main() {
  late PointerValues native;
  setUpAll(() {
    native = PointerValues();
    addTearDown(native.close);
  });

  test('pointer identity survives generics, captures, fields, exceptions and collection', () {
    for (final address in [0, -1, 16, 0x7fffffffffffffff]) {
      final pointer = Pointer<Int64>.fromAddress(address);
      for (final count in [0, 40000]) {
        expect(sdk.pointerValues(pointer, count), 511);
        expect(native.values(pointer, count), 511);
      }
    }
  });

  test('nullable pointer aliases remain rooted between native entries', () {
    for (final address in [0, -1, 48]) {
      for (final mode in [0, 1, 1]) {
        expect(sdk.persistentPointer(mode, address, 40000), 1);
        expect(native.persistent(mode, address, 40000), 1);
      }
    }
  });

  test('identical retains integer values and floating bit patterns', () {
    double bits(int value) => (ByteData(8)..setInt64(0, value)).getFloat64(0);
    final nan = bits(0x7ff8000000000001);
    for (final (a, b, x, y, expected) in [
      (1, 1, 1.0, 1.0, 63),
      (1, 2, 0.0, -0.0, 48),
      (0x20000000000000, 0x20000000000001, nan, nan, 60),
      (-1, -1, nan, bits(0x7ff8000000000002), 51),
      (0, 0, double.infinity, double.infinity, 63),
    ]) {
      expect(sdk.scalarIdentity(a, b, x, y), expected);
      expect(native.scalars(a, b, x, y), expected);
    }
  });

  test('indirect native calls unwrap arguments and wrap returned pointers', () {
    final provider = NativeAssets(Target.host())
        .open('compiler/native_function_pointers');
    addTearDown(provider.close);
    final echo = provider.lookup<NativeFunction<sdk.EchoNative>>('opaque');
    for (final address in [0, -1, 64]) {
      final pointer = Pointer<Void>.fromAddress(address);
      expect(sdk.indirectPointer(echo, pointer, 40000), 1);
      expect(native.indirect(echo, pointer, 40000), 1);
    }
  });
}
