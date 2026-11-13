import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

final class ManagedObjects() {
  final _library = NativeAssets(Target.host()).open('compiler/managed_objects');
  final _storage = NativeAssets(Target.host())
      .open('compiler/managed_objects_storage');
  late final output = _storage.lookup<Int64>('counter');
  late final floatingOutput = _storage.lookup<Double>('state');
  late final constructStackPointer = _library
      .lookupFunction<
        Void Function(Pointer<Int64>),
        void Function(Pointer<Int64>)
      >('constructStackPointer');
  late final constructNumbers = _library
      .lookupFunction<
        Void Function(Int64, Double, Int64, Pointer<Int64>, Pointer<Double>),
        void Function(int, double, int, Pointer<Int64>, Pointer<Double>)
      >('constructNumbers');
  late final allocateAndNotify = _library
      .lookupFunction<
        Float Function(Int32, Double, Pointer<Int64>),
        double Function(int, double, Pointer<Int64>)
      >('allocateAndNotify');

  void close() {
    _library.close();
    _storage.close();
  }
}
