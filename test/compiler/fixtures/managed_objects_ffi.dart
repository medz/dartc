import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

final class ManagedObjects() {
  final _library = NativeAssets(Target.host()).open('compiler/managed_objects');
  final _storage = NativeAssets(Target.host()).open('compiler/pointer_storage');
  late final output = _storage.lookup<Int64>('counter');
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
