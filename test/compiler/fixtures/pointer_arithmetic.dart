// ignore_for_file: deprecated_member_use

import 'dart:ffi';

import 'package:dartc/interop.dart';

@Export<Int64 Function(Int64, Int64, Int64)>()
int offsetInt8(int address, int index, int operation) {
  final pointer = Pointer<Int8>.fromAddress(address);
  return switch (operation) {
    0 => (pointer + index).address,
    1 => (pointer - index).address,
    _ => pointer.elementAt(index).address,
  };
}

@Export<Int64 Function(Int64, Int64, Int64)>()
int indexedInt8(int address, int index, int value) {
  final pointer = Pointer<Int8>.fromAddress(address);
  pointer[index] = value;
  return pointer[index];
}

@Export<Int64 Function(Int64, Int64, Int64)>()
int offsetUint8(int address, int index, int operation) {
  final pointer = Pointer<Uint8>.fromAddress(address);
  return switch (operation) {
    0 => (pointer + index).address,
    1 => (pointer - index).address,
    _ => pointer.elementAt(index).address,
  };
}

@Export<Int64 Function(Int64, Int64, Int64)>()
int indexedUint8(int address, int index, int value) {
  final pointer = Pointer<Uint8>.fromAddress(address);
  pointer[index] = value;
  return pointer[index];
}

@Export<Int64 Function(Int64, Int64, Int64)>()
int offsetInt16(int address, int index, int operation) {
  final pointer = Pointer<Int16>.fromAddress(address);
  return switch (operation) {
    0 => (pointer + index).address,
    1 => (pointer - index).address,
    _ => pointer.elementAt(index).address,
  };
}

@Export<Int64 Function(Int64, Int64, Int64)>()
int indexedInt16(int address, int index, int value) {
  final pointer = Pointer<Int16>.fromAddress(address);
  pointer[index] = value;
  return pointer[index];
}

@Export<Int64 Function(Int64, Int64, Int64)>()
int offsetUint16(int address, int index, int operation) {
  final pointer = Pointer<Uint16>.fromAddress(address);
  return switch (operation) {
    0 => (pointer + index).address,
    1 => (pointer - index).address,
    _ => pointer.elementAt(index).address,
  };
}

@Export<Int64 Function(Int64, Int64, Int64)>()
int indexedUint16(int address, int index, int value) {
  final pointer = Pointer<Uint16>.fromAddress(address);
  pointer[index] = value;
  return pointer[index];
}

@Export<Int64 Function(Int64, Int64, Int64)>()
int offsetInt32(int address, int index, int operation) {
  final pointer = Pointer<Int32>.fromAddress(address);
  return switch (operation) {
    0 => (pointer + index).address,
    1 => (pointer - index).address,
    _ => pointer.elementAt(index).address,
  };
}

@Export<Int64 Function(Int64, Int64, Int64)>()
int indexedInt32(int address, int index, int value) {
  final pointer = Pointer<Int32>.fromAddress(address);
  pointer[index] = value;
  return pointer[index];
}

@Export<Int64 Function(Int64, Int64, Int64)>()
int offsetUint32(int address, int index, int operation) {
  final pointer = Pointer<Uint32>.fromAddress(address);
  return switch (operation) {
    0 => (pointer + index).address,
    1 => (pointer - index).address,
    _ => pointer.elementAt(index).address,
  };
}

@Export<Int64 Function(Int64, Int64, Int64)>()
int indexedUint32(int address, int index, int value) {
  final pointer = Pointer<Uint32>.fromAddress(address);
  pointer[index] = value;
  return pointer[index];
}

@Export<Int64 Function(Int64, Int64, Int64)>()
int offsetInt64(int address, int index, int operation) {
  final pointer = Pointer<Int64>.fromAddress(address);
  return switch (operation) {
    0 => (pointer + index).address,
    1 => (pointer - index).address,
    _ => pointer.elementAt(index).address,
  };
}

@Export<Int64 Function(Int64, Int64, Int64)>()
int indexedInt64(int address, int index, int value) {
  final pointer = Pointer<Int64>.fromAddress(address);
  pointer[index] = value;
  return pointer[index];
}

@Export<Int64 Function(Int64, Int64, Int64)>()
int offsetUint64(int address, int index, int operation) {
  final pointer = Pointer<Uint64>.fromAddress(address);
  return switch (operation) {
    0 => (pointer + index).address,
    1 => (pointer - index).address,
    _ => pointer.elementAt(index).address,
  };
}

@Export<Int64 Function(Int64, Int64, Int64)>()
int indexedUint64(int address, int index, int value) {
  final pointer = Pointer<Uint64>.fromAddress(address);
  pointer[index] = value;
  return pointer[index];
}

@Export<Int64 Function(Int64, Int64, Int64)>()
int offsetFloat(int address, int index, int operation) {
  final pointer = Pointer<Float>.fromAddress(address);
  return switch (operation) {
    0 => (pointer + index).address,
    1 => (pointer - index).address,
    _ => pointer.elementAt(index).address,
  };
}

@Export<Double Function(Int64, Int64, Double)>()
double indexedFloat(int address, int index, double value) {
  final pointer = Pointer<Float>.fromAddress(address);
  pointer[index] = value;
  return pointer[index];
}

@Export<Int64 Function(Int64, Int64, Int64)>()
int offsetDouble(int address, int index, int operation) {
  final pointer = Pointer<Double>.fromAddress(address);
  return switch (operation) {
    0 => (pointer + index).address,
    1 => (pointer - index).address,
    _ => pointer.elementAt(index).address,
  };
}

@Export<Double Function(Int64, Int64, Double)>()
double indexedDouble(int address, int index, double value) {
  final pointer = Pointer<Double>.fromAddress(address);
  pointer[index] = value;
  return pointer[index];
}

@Export<Int64 Function(Pointer<Int64>, Pointer<Int64>, Int64)>()
int update(Pointer<Int64> trace, Pointer<Int64> pointer, int index) {
  final old = receiver(trace, pointer)[key(trace, index)]++;
  receiver(trace, pointer)[key(trace, index)] += operand(trace);
  return old * 100 + ++receiver(trace, pointer)[key(trace, index)];
}

Pointer<Int64> receiver(Pointer<Int64> trace, Pointer<Int64> pointer) {
  trace.value = trace.value * 10 + 1;
  return pointer;
}

int key(Pointer<Int64> trace, int index) {
  trace.value = trace.value * 10 + 2;
  return index;
}

int operand(Pointer<Int64> trace) {
  trace.value = trace.value * 10 + 3;
  return 7;
}

Pointer<Int64> advance(Pointer<Int64> pointer, int offset) => pointer + offset;

@Export<Int64 Function(Pointer<Int64>, Int64)>()
int sum(Pointer<Int64> pointer, int count) {
  var result = 0;
  for (var i = 0; i < count; i++) {
    result += pointer[0];
    pointer = advance(pointer, 1);
  }
  return result;
}
