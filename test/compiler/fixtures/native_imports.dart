@DefaultAsset('math:first')
library;

import 'dart:ffi';

import 'package:dartc/interop.dart';

@Native<Int64 Function(Int8)>(symbol: 'step', isLeaf: true)
external int first(int value);

class Other() {
  @Native<Int64 Function(Int8)>(assetId: 'math:second', symbol: 'step')
  external static int second(int value);
}

@Native<Pointer<Void> Function(Pointer<Void>)>(symbol: 'pointer')
external Pointer<NativeType> pointer(Pointer<Void> value);

@Native<Double Function(Double)>(assetId: 'unused')
external double unused(double value);

@Export<Int64 Function(Int64)>()
int runImports(int value) {
  final left = first(value);
  final right = Other.second(value);
  return left * 1000 + right;
}

@Export<Int64 Function(Pointer<Void>)>()
int pointerResult(Pointer<Void> value) => pointer(value).address;
