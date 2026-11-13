import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

final class PointerArithmeticLibrary() {
  final _library = NativeAssets(Target.host())
      .open('compiler/pointer_arithmetic');
  final _storage = NativeAssets(Target.host())
      .open('compiler/pointer_arithmetic_storage');
  late final memory = _storage.lookup<Int64>('counter');

  int Function(int, int, int) offset(String type) =>
      _library.lookupFunction<
        Int64 Function(Int64, Int64, Int64),
        int Function(int, int, int)
      >('offset$type');

  int Function(int, int, int) indexedInteger(String type) =>
      _library.lookupFunction<
        Int64 Function(Int64, Int64, Int64),
        int Function(int, int, int)
      >('indexed$type');

  double Function(int, int, double) indexedFloat(String type) =>
      _library.lookupFunction<
        Double Function(Int64, Int64, Double),
        double Function(int, int, double)
      >('indexed$type');

  late final update = _library
      .lookupFunction<
        Int64 Function(Pointer<Int64>, Pointer<Int64>, Int64),
        int Function(Pointer<Int64>, Pointer<Int64>, int)
      >('update');
  late final sum = _library
      .lookupFunction<
        Int64 Function(Pointer<Int64>, Int64),
        int Function(Pointer<Int64>, int)
      >('sum');

  void close() {
    _library.close();
    _storage.close();
  }
}
