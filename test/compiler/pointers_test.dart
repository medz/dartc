@Tags(['assets', 'native'])
library;

import 'dart:ffi';

import 'package:test/test.dart';

import 'fixtures/pointers.dart' as sdk;
import 'fixtures/pointers_ffi.dart';

void main() {
  late PointerLibrary library;
  late Pointer<Int64> memory;
  setUpAll(() {
    library = PointerLibrary();
    addTearDown(library.close);
    memory = library.memory;
  });

  test('pointer bits round-trip independently of integer values', () {
    for (final bits in [
      0,
      1,
      -1,
      -0x8000000000000000,
      0x7fffffffffffffff,
      memory.address,
    ]) {
      final pointer = library.fromAddress(bits),
          expected = sdk.fromAddress(bits);
      expect(pointer.address, expected.address);
      expect(library.address(pointer), sdk.address(expected));
      expect(library.equal(pointer, expected), sdk.equal(pointer, expected));
      expect(library.equal(pointer, memory), sdk.equal(pointer, memory));
    }
    expect(library.declaredMember(memory), 73);
  });

  test('native writes and subsequent reads preserve integer boundary bits', () {
    for (final value in [
      0,
      -1,
      0x123456789ab,
      -0x8000000000000000,
      0x7fffffffffffffff,
    ]) {
      library.write(memory, value);
      expect(memory.value, value);
      expect(library.read(memory), sdk.read(memory));
      sdk.write(memory, ~value);
      expect(library.read(memory), ~value);
    }
  });

  test('pointer slots preserve bits, aliases and adjacent storage', () {
    final bytes = memory.cast<Uint8>().asTypedList(96);
    final slots = (memory + 4).cast<Pointer<Int64>>();
    for (final index in [-2, 0, 2]) {
      for (final bits in [0, -1, -0x8000000000000000, memory.address]) {
        bytes.fillRange(0, bytes.length, 0xa5);
        slots[index] = memory;
        final value = Pointer<Int64>.fromAddress(bits);
        final actual = library.exchangePointer(slots, index, value);
        final contents = bytes.toList();
        bytes.fillRange(0, bytes.length, 0xa5);
        slots[index] = memory;
        expect(actual, sdk.exchangePointer(slots, index, value));
        expect(contents, bytes);
        expect(slots[index], value);
      }
    }
    for (final index in [0, 1]) {
      slots[0] = memory;
      slots[1] = memory + 1;
      final actual = library.swapSlots(slots, index);
      final values = [slots[0], slots[1]];
      slots[0] = memory;
      slots[1] = memory + 1;
      expect(actual, sdk.swapSlots(slots, index));
      expect(values, [slots[0], slots[1]]);
    }
  });

  test('pointer slot offsets scale addresses without accessing storage', () {
    for (final bits in [0, -1, 0x7fffffffffffffff]) {
      final slots = Pointer<Pointer<Int64>>.fromAddress(bits);
      for (final index in [0, -3, 7, -0x8000000000000000]) {
        for (var operation = 0; operation < 3; operation++) {
          expect(
            library.offsetSlots(slots, index, operation),
            sdk.offsetSlots(slots, index, operation),
          );
        }
      }
    }
  });

  test('loaded pointers survive collection and retain callable signatures', () {
    final slots = (memory + 4).cast<Pointer<Int64>>();
    slots[0] = memory;
    slots[1] = memory + 1;
    memory.value = 73;
    expect(library.retainSlot(slots, 4000), memory);
    final callbacks = slots.cast<sdk.ReadPointer>();
    callbacks.value = library.readPointer;
    expect(library.readThroughSlot(callbacks, memory), 73);
  });

  test(
    'pointer transfers across loops, branches and calls retain identity',
    () {
      for (final count in [-1, 0, 1, 2, 11]) {
        memory.value = 3;
        (memory + 1).value = 5;
        final result = library.rotate(memory, memory + 1, count);
        final values = [memory.value, (memory + 1).value];
        memory.value = 3;
        (memory + 1).value = 5;
        expect(result.address, sdk.rotate(memory, memory + 1, count).address);
        expect(values, [memory.value, (memory + 1).value]);
      }
    },
  );

  test('compound pointer writes preserve receiver order and aliases', () {
    for (final alias in [false, true]) {
      final target = alias ? memory : memory + 1;
      memory.value = 0;
      if (!alias) target.value = 5;
      final actual = library.update(memory, target);
      final values = [memory.value, target.value];
      memory.value = 0;
      if (!alias) target.value = 5;
      expect(actual, sdk.update(memory, target));
      expect(values, [memory.value, target.value]);
    }
  });

  test(
    'mixed pointer and integer arguments use native registers and stack slots',
    () {
      for (final (native, expected) in [
        (library.mixed, sdk.mixed),
        (library.forward, sdk.forward),
      ]) {
        for (final alias in [false, true]) {
          final pointers = [
            for (var i = 0; i < 5; i++) memory + (alias ? 0 : i),
          ];
          void reset() {
            for (var i = 0; i < 5; i++) {
              (memory + i).value = 0x12345678000 + i;
            }
          }

          reset();
          final result = native(
            pointers[0],
            -1,
            pointers[1],
            2,
            pointers[2],
            -3,
            pointers[3],
            4,
            pointers[4],
            -5,
          );
          final values = [for (var i = 0; i < 5; i++) (memory + i).value];
          reset();
          expect(
            result.address,
            expected(
              pointers[0],
              -1,
              pointers[1],
              2,
              pointers[2],
              -3,
              pointers[3],
              4,
              pointers[4],
              -5,
            ).address,
          );
          expect(values, [for (var i = 0; i < 5; i++) (memory + i).value]);
        }
      }
    },
  );
}
