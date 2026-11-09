import 'dart:ffi' as ffi;

final class Pointer(final int address);

extension Int64Pointer on ffi.Pointer<ffi.Int64> {
  int get value => 73;
  ffi.Pointer<ffi.Int64> operator +(int offset) => this;
  int operator [](int index) => 70 + index;
}

int customMember(ffi.Pointer<ffi.Int64> pointer) => Int64Pointer(pointer).value;
int ordinaryPointer(int address) => Pointer(address).address;
int customOffset(ffi.Pointer<ffi.Int64> pointer) =>
    (Int64Pointer(pointer) + 5).address;
int customIndex(ffi.Pointer<ffi.Int64> pointer) => Int64Pointer(pointer)[7];
