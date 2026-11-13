@Tags(['assets', 'native'])
library;

import 'dart:ffi';

import 'package:test/test.dart';

import 'fixtures/native_addresses_ffi.dart';

void main() {
  late NativeAddresses native;
  setUpAll(() {
    native = NativeAddresses();
    addTearDown(native.close);
  });

  test('native writes alias all typed-list widths and subview offsets', () {
    expect(
      [for (var i = 0; i < 8; i++) native.integerLists(i)],
      [
        -7,
        251,
        -31999,
        65000,
        -2000000000,
        4000000000,
        -0x123456789abcdef,
        0x123456789abcdef,
      ],
    );
    expect(native.floatingLists(true), -1.25);
    expect(native.floatingLists(false), 1.125);
    expect(native.subviews(), isTrue);
  });

  test('compound, array and scalar addresses refer to the owning storage', () {
    final state = native.compounds();
    expect((state.count, state.value, state.enabled), (-321, 2.5, true));
    expect(state.entries.elements, [11, 33, 33]);
  });

  test(
    'later arguments preserve temporary owners and may prevent the call',
    () {
      final system = DynamicLibrary.process();
      final allocate = system
          .lookupFunction<
            Pointer<Uint8> Function(UintPtr),
            Pointer<Uint8> Function(int)
          >('malloc');
      final release = system
          .lookupFunction<
            Void Function(Pointer<Uint8>),
            void Function(Pointer<Uint8>)
          >('free');
      final bytes = allocate(2);
      addTearDown(() => release(bytes));
      expect(native.ordered(bytes, false), 12);
      expect(bytes.asTypedList(2), [9, 8]);
      bytes[0] = 5;
      bytes[1] = 6;
      expect(native.ordered(bytes, true), 123);
      expect(bytes.asTypedList(2), [5, 6]);
    },
  );
}
