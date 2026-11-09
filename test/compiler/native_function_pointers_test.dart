@Tags(['assets', 'native'])
library;

import 'dart:ffi';

import 'package:test/test.dart';

import 'fixtures/native_function_pointers_ffi.dart';
import 'fixtures/native_function_pointers.dart' show FactoryNative;

void main() {
  late NativeFunctionPointers library;
  setUpAll(() {
    library = NativeFunctionPointers();
    addTearDown(library.close);
  });

  test(
    'native function pointers retain signatures and remain callable by SDK FFI',
    () {
      for (final (pointer, delta) in [
        (library.increment, 7),
        (library.decrement, -11),
      ]) {
        final result = library.identity(pointer);
        expect(result.address, pointer.address);
        expect(library.address(result), pointer.address);
        expect(library.fromAddress(pointer.address).address, pointer.address);
        final invoke = result.asFunction<int Function(int)>(isLeaf: true);
        for (final value in [-129, 0, 129, 255]) {
          expect(invoke(value), value.toSigned(8) + delta);
        }
        final factory = library.nested(library.factory);
        expect(factory.address, library.factory.address);
        expect(
          factory.asFunction<FactoryNative>()(pointer).address,
          pointer.address,
        );
      }
      for (final address in [0, -1, 0x7fffffffffffffff]) {
        expect(library.address(library.fromAddress(address)), address);
        expect(
          library.opaque(Pointer<Void>.fromAddress(address)).address,
          address,
        );
      }
    },
  );

  test(
    'function pointer stack arguments and live values survive calls and loops',
    () {
      final a = library.increment, b = library.decrement;
      for (final count in [-1, 0, 1, 2, 5]) {
        final result = library.select(a, a, b, b, a, a, b, b, b, b, count);
        expect(result.address, (count < 0 || count.isOdd ? b : a).address);
        expect(
          result.asFunction<int Function(int)>()(129),
          -127 + (result.address == a.address ? 7 : -11),
        );
      }
    },
  );

  test(
    'pointer equality depends on addresses across different element types',
    () {
      for (final address in [
        0,
        -1,
        0x7fffffffffffffff,
        library.increment.address,
      ]) {
        final pointer = library.fromAddress(address);
        for (final other in [address, address + 1]) {
          final opaque = Pointer<Void>.fromAddress(other);
          expect(
            library.sameAddress(pointer, opaque),
            address == other ? 1 : 0,
          );
          expect(
            library.differentAddress(opaque, pointer),
            address != other ? 1 : 0,
          );
        }
      }
    },
  );
}
