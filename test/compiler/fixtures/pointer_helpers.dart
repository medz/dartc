import 'dart:ffi' as ffi;

final class Pointer(final int address);

extension Int64Pointer on ffi.Pointer<ffi.Int64> {
  int get value => 73;
}

int customMember(ffi.Pointer<ffi.Int64> pointer) => Int64Pointer(pointer).value;
int ordinaryPointer(int address) => Pointer(address).address;
