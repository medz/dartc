// FFI storage subclasses cannot declare generative constructors.
// ignore_for_file: use_primary_constructors

import 'dart:ffi';
import 'dart:typed_data';

import 'package:dartc/interop.dart';

final class MemoryReport extends Struct {
  @Int64()
  external int integers;
  @Double()
  external double floating;
  @Uint64()
  external int bits;
  @Int32()
  external int length;
  @Bool()
  external bool immutable;
}

@Export<MemoryReport Function(Int64, Double)>()
MemoryReport typedLists(int seed, double number) {
  final signed = Int8List.fromList([seed, -129]);
  final unsigned = Uint8List.fromList([seed, -1]);
  final clamped = Uint8ClampedList.fromList([-1, 256, seed]);
  final i16 = Int16List.fromList([seed + 0xffff]);
  final u16 = Uint16List.fromList([seed + 0xffff]);
  final i32 = Int32List.fromList([seed + 0xffffffff]);
  final u32 = Uint32List.fromList([seed + 0xffffffff]);
  final i64 = Int64List.fromList([seed]);
  final u64 = Uint64List.fromList([-1]);
  final f32 = Float32List.fromList([number]);
  final f64 = Float64List.fromList([number]);
  final result = Struct.create<MemoryReport>();
  result.integers =
      signed[0] +
      signed[1] +
      unsigned[0] +
      unsigned[1] +
      clamped[0] +
      clamped[1] +
      clamped[2] +
      i16[0] +
      u16[0] +
      i32[0] +
      u32[0] +
      i64[0];
  result.floating = f32[0] + f64[0];
  result.bits = u64[0];
  result.length = f64.elementSizeInBytes;
  return result;
}

@Export<MemoryReport Function(Double)>()
MemoryReport byteViews(double value) {
  final bytes = ByteData(32);
  bytes.setFloat32(3, value);
  bytes.setFloat64(9, -value, Endian.little);
  bytes.setInt16(1, -0x1234);
  bytes.setUint32(21, 0x89abcdef, Endian.little);
  final words = Uint16List.view(bytes.buffer, 20, 3);
  final view = ByteData.sublistView(words, 1, 3);
  final result = Struct.create<MemoryReport>();
  result.integers = bytes.getInt16(1);
  result.floating = bytes.getFloat32(3) + bytes.getFloat64(9, Endian.little);
  result.bits = view.getUint16(0, Endian.little);
  result.length = view.offsetInBytes;
  result.immutable = Endian.host == Endian.little;
  return result;
}

@Export<Int64 Function()>()
int overlappingTypedViews() {
  final bytes = Uint8List.fromList([1, 2, 3, 4, 5, 6]);
  final view = Uint8List.view(bytes.buffer, 1, 4);
  view.setRange(0, 4, bytes);
  bytes.setRange(0, 4, view, 0);
  var result = 0;
  for (final byte in bytes) {
    result = result * 10 + byte;
  }
  return result;
}

@Export<Int32 Function()>()
int readonlyTypedViews() {
  final original = Uint8List.fromList([2, 3, 4]);
  final view = original.asUnmodifiableView();
  var rejected = 0;
  try {
    view[0] = 5;
  } on UnsupportedError {
    rejected++;
  }
  try {
    view.buffer.asByteData().setUint8(0, 6);
  } on UnsupportedError {
    rejected++;
  }
  try {
    view.setRange(0, 0, const <int>[]);
  } on UnsupportedError {
    rejected++;
  }
  final copy = view.sublist(1);
  copy[0] = 9;
  original[1] = 7;
  return rejected * 100 + view[1] * 10 + copy[0];
}

@Export<Bool Function(Int32)>()
bool typedBounds(int mode) {
  try {
    switch (mode) {
      case 0:
        Uint8List(-1);
      case 1:
        ByteData(-1);
      case 2:
        Uint8List(0)[0];
      case 3:
        ByteData(2).getInt32(0);
      case 4:
        Uint16List.view(Uint8List(4).buffer, 1);
      case 5:
        Uint16List.view(Uint8List(4).buffer, 0, 3);
      case 6:
        Uint8List(1)[-1] = 0;
      case 7:
        Struct.create<Samples>(Uint8List(8), -1);
      case 8:
        Struct.create<Samples>(Uint8List(8), 1);
    }
    return false;
  } on ArgumentError {
    return true;
  }
}

final class Samples extends Struct {
  @Array(4)
  external Array<Int16> values;
}

final class FloatBits extends Union {
  @Uint64()
  external int bits;
  @Double()
  external double number;
}

@Export<MemoryReport Function(Int32)>()
MemoryReport sharedNativeViews(int value) {
  final data = Uint16List(16);
  data[0] = 0x55aa;
  final window = Uint16List.sublistView(data, 2, 10);
  final sample = Struct.create<Samples>(window, 1);
  final elements = sample.values.elements;
  elements[1] = value;
  for (var i = 0; i < 20000; i++) {
    ByteData(64);
  }
  final bytes = ByteData.view(data.buffer);
  final report = Struct.create<MemoryReport>();
  report.integers = bytes.getInt16(8, Endian.host);
  bytes.setInt16(10, -7, Endian.host);
  report.bits = data[0];
  report.floating = elements[2].toDouble();
  report.length = elements.length;
  report.immutable = sample.values[1] == elements[1];
  return report;
}

@Export<Bool Function(Int32)>()
bool typedCollections(int mode) {
  switch (mode) {
    case 0:
      final integers = Int8List.fromList([-1]) + Uint16List.fromList([65535]);
      final floats = Float32List.fromList([1.25]) + Float64List.fromList([2.5]);
      return integers is TypedData &&
          floats is TypedData &&
          integers[0] == -1 &&
          integers[1] == 65535 &&
          floats[1] == 2.5;
    case 1:
      final data = Uint16List.fromList([0x1234, 0x5678, 0x9abc]);
      final bytes = data.buffer.asUint8List();
      bytes.setRange(2, 5, data);
      return bytes[2] == 0x34 && bytes[3] == 0x78 && bytes[4] == 0xbc;
    case 2:
      final values = Uint8List(1).asUnmodifiableView();
      values.setRange(0, 0, values);
      try {
        values.setRange(0, 0, values, 2);
      } on StateError {
        return true;
      }
      return false;
    default:
      final bytes = ByteData(8);
      bytes.setFloat64(0, -0.0);
      if (bytes.getInt64(0) != -9223372036854775808) return false;
      bytes.setFloat32(0, double.infinity);
      if (bytes.getUint32(0) != 0x7f800000) return false;
      final union = Union.create<FloatBits>(bytes);
      union.number = -0.0;
      return union.bits == -9223372036854775808;
  }
}
