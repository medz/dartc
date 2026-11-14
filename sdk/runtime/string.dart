import 'dart:ffi';

import '../../lib/layout/memory.dart';
import '../../lib/runtime/contracts.dart';

import 'memory.dart';

/// Target UTF-16 storage. Callers own initialization and access bounds.
abstract final class StringStorage() {
  static const maximumLength =
      (0x1ffffffffffffff8 - ObjectHeader.fieldsOffset - 8) ~/ 2;
  @Primitive(.allocatePayload)
  external static String _allocate(int bytes);

  static int bytesFor(int length) =>
      length < 0 || length > maximumLength ? -1 : length * 2;

  static void initialize(String string, int length) {
    Pointer<Int64>.fromAddress(
      Memory.addressOf(string) + ObjectHeader.fieldsOffset,
    ).value = length;
  }

  static String create(int length) {
    final result = _allocate(bytesFor(length));
    initialize(result, length);
    return result;
  }

  static void copy(
    String source,
    int start,
    int end,
    String destination,
    int offset,
  ) {
    for (var i = start; i < end; i++) {
      write(destination, offset++, read(source, i));
    }
  }

  static int read(String string, int index) {
    final address =
        Memory.addressOf(string) + ObjectHeader.fieldsOffset + 8 + index * 2;
    return Pointer<Uint8>.fromAddress(address).value |
        (Pointer<Uint8>.fromAddress(address + 1).value << 8);
  }

  static void write(String string, int index, int value) {
    final address =
        Memory.addressOf(string) + ObjectHeader.fieldsOffset + 8 + index * 2;
    Pointer<Uint8>.fromAddress(address).value = value;
    Pointer<Uint8>.fromAddress(address + 1).value = value >> 8;
  }
}
