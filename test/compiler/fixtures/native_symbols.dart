@DefaultAsset('native-symbols')
library;

import 'dart:ffi';

import 'package:dartc/interop.dart';

import 'native_symbols_types.dart';

@Native<Int16>(symbol: 'integer')
external int number;

@Native<Float>(symbol: 'floating')
external double single;

@Native(symbol: 'pointer')
external Pointer<Int16> pointer;

@Native(symbol: 'pair')
external NativePair pair;

@Native<Bool>(symbol: 'boolean')
external bool flag;

@Native<Int64>(assetId: 'unused')
external int absent;

abstract final class Fields() {
  @Native<Int64>(symbol: 'read_only')
  external static final int constant;

  @Native<Double>(symbol: 'floating')
  external static double get real;

  @Native<Int64 Function(Int64)>(symbol: 'add')
  external static int add(int value);
}

@Export<Int64 Function(Int64)>()
int exchangeInteger(int value) {
  final previous = number;
  number = value;
  return previous;
}

@Export<Double Function(Double)>()
double storeFloat(double value) => single = value;

@Export<Double Function()>()
double readFloat() => single;

@Export<Bool Function(Bool)>()
bool storeBool(bool value) => flag = value;

@Export<Pointer<Int16> Function()>()
Pointer<Int16> integerAddress() => Native.addressOf(number);

@Export<Pointer<Double> Function()>()
Pointer<Double> doubleAddress() => Native.addressOf(Fields.real);

@Export<Pointer<Pointer<Int16>> Function()>()
Pointer<Pointer<Int16>> pointerAddress() => Native.addressOf(pointer);

@Export<Pointer<Int16> Function(Pointer<Int16>)>()
Pointer<Int16> exchangePointer(Pointer<Int16> value) {
  final previous = pointer;
  pointer = value;
  return previous;
}

@Export<Void Function(NativePair)>()
void storePair(NativePair value) => pair = value;

@Export<NativePair Function()>()
NativePair readPair() => pair;

@Export<Pointer<NativePair> Function()>()
Pointer<NativePair> pairAddress() => Native.addressOf(pair);

@Export<Int64 Function()>()
int readConstant() => Fields.constant;

@Export<Pointer<NativeFunction<Int64 Function(Int64)>> Function()>()
Pointer<NativeFunction<Int64 Function(Int64)>> functionAddress() =>
    Native.addressOf(Fields.add);

@Export<Int64 Function(Int64)>()
int callAddress(int value) =>
    functionAddress().asFunction<int Function(int)>()(value);
