import 'dart:ffi';

int boundedOffset(int address, int index) {
  if (index < 0 || index >= 4) return -1;
  final pointer = Pointer<Int64>.fromAddress(address);
  return (pointer + index).address - address;
}
