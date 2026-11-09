import 'dart:ffi';

import 'package:dartc/interop.dart';

@Export<Int64 Function(Int64)>()
int readInt8(int address) => Pointer<Int8>.fromAddress(address).value;

@Export<Int64 Function(Int64, Int64)>()
int writeInt8(int address, int value) {
  final pointer = Pointer<Int8>.fromAddress(address);
  pointer.value = value;
  return pointer.value;
}

@Export<Int64 Function(Int8)>()
int extendInt8(int value) => value;

@Export<Int8 Function(Int64)>()
int truncateInt8(int value) => value;

@Export<Int64 Function(Int64)>()
int readUint8(int address) => Pointer<Uint8>.fromAddress(address).value;

@Export<Int64 Function(Int64, Int64)>()
int writeUint8(int address, int value) {
  final pointer = Pointer<Uint8>.fromAddress(address);
  pointer.value = value;
  return pointer.value;
}

@Export<Int64 Function(Uint8)>()
int extendUint8(int value) => value;

@Export<Uint8 Function(Int64)>()
int truncateUint8(int value) => value;

@Export<Int64 Function(Int64)>()
int readInt16(int address) => Pointer<Int16>.fromAddress(address).value;

@Export<Int64 Function(Int64, Int64)>()
int writeInt16(int address, int value) {
  final pointer = Pointer<Int16>.fromAddress(address);
  pointer.value = value;
  return pointer.value;
}

@Export<Int64 Function(Int16)>()
int extendInt16(int value) => value;

@Export<Int16 Function(Int64)>()
int truncateInt16(int value) => value;

@Export<Int64 Function(Int64)>()
int readUint16(int address) => Pointer<Uint16>.fromAddress(address).value;

@Export<Int64 Function(Int64, Int64)>()
int writeUint16(int address, int value) {
  final pointer = Pointer<Uint16>.fromAddress(address);
  pointer.value = value;
  return pointer.value;
}

@Export<Int64 Function(Uint16)>()
int extendUint16(int value) => value;

@Export<Uint16 Function(Int64)>()
int truncateUint16(int value) => value;

@Export<Int64 Function(Int64)>()
int readInt32(int address) => Pointer<Int32>.fromAddress(address).value;

@Export<Int64 Function(Int64, Int64)>()
int writeInt32(int address, int value) {
  final pointer = Pointer<Int32>.fromAddress(address);
  pointer.value = value;
  return pointer.value;
}

@Export<Int64 Function(Int32)>()
int extendInt32(int value) => value;

@Export<Int32 Function(Int64)>()
int truncateInt32(int value) => value;

@Export<Int64 Function(Int64)>()
int readUint32(int address) => Pointer<Uint32>.fromAddress(address).value;

@Export<Int64 Function(Int64, Int64)>()
int writeUint32(int address, int value) {
  final pointer = Pointer<Uint32>.fromAddress(address);
  pointer.value = value;
  return pointer.value;
}

@Export<Int64 Function(Uint32)>()
int extendUint32(int value) => value;

@Export<Uint32 Function(Int64)>()
int truncateUint32(int value) => value;

@Export<Int64 Function(Int64)>()
int readInt64(int address) => Pointer<Int64>.fromAddress(address).value;

@Export<Int64 Function(Int64, Int64)>()
int writeInt64(int address, int value) {
  final pointer = Pointer<Int64>.fromAddress(address);
  pointer.value = value;
  return pointer.value;
}

@Export<Int64 Function(Int64)>()
int readUint64(int address) => Pointer<Uint64>.fromAddress(address).value;

@Export<Int64 Function(Int64, Int64)>()
int writeUint64(int address, int value) {
  final pointer = Pointer<Uint64>.fromAddress(address);
  pointer.value = value;
  return pointer.value;
}

@Export<Int8 Function(Int8)>()
int narrow(int value) => value + 1;

@Export<Int64 Function(Int64)>()
int internal(int value) =>
    narrow(value) + truncateInt8(value) + extendInt8(value);

@Export<Uint64 Function(Uint64)>()
int unsigned64(int value) => value;

@Export<Pointer<Uint16> Function(Int64)>()
Pointer<Uint16> fromAddress(int address) => .fromAddress(address);

@Export<Int64 Function(Pointer<Uint16>, Pointer<Int8>, Int64)>()
int update(Pointer<Uint16> first, Pointer<Int8> second, int value) {
  first.value += value;
  second.value++;
  return first.value + second.value;
}

typedef MixedNative = Double Function(
  Int8,
  Uint8,
  Int16,
  Uint16,
  Int32,
  Uint32,
  Int64,
  Uint64,
  Double,
  Double,
  Double,
  Double,
  Double,
  Double,
  Double,
  Double,
  Int8,
  Uint16,
  Double,
  Int32,
  Pointer<Uint16>,
);
typedef MixedDart = double Function(
  int,
  int,
  int,
  int,
  int,
  int,
  int,
  int,
  double,
  double,
  double,
  double,
  double,
  double,
  double,
  double,
  int,
  int,
  double,
  int,
  Pointer<Uint16>,
);

@Export<MixedNative>()
double mixed(
  int a0,
  int a1,
  int a2,
  int a3,
  int a4,
  int a5,
  int a6,
  int a7,
  double a8,
  double a9,
  double a10,
  double a11,
  double a12,
  double a13,
  double a14,
  double a15,
  int a16,
  int a17,
  double a18,
  int a19,
  Pointer<Uint16> a20,
) =>
    a0 +
    a1 +
    a2 +
    a3 +
    a4 +
    a5 +
    a6 +
    a7 +
    a8 +
    a9 +
    a10 +
    a11 +
    a12 +
    a13 +
    a14 +
    a15 +
    a16 +
    a17 +
    a18 +
    a19 +
    a20.value;
