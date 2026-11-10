import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

final class Exceptions() {
  final _library = NativeAssets(Target.host()).open('compiler/exceptions');
  final _storage = NativeAssets(Target.host()).open('compiler/pointer_storage');
  late final effects = _storage.lookup<Int64>('counter');
  late final cleanup = _library
      .lookupFunction<
        Int64 Function(Int64, Int64, Pointer<Int64>),
        int Function(int, int, Pointer<Int64>)
      >('cleanup');
  late final constructorFailure = _library
      .lookupFunction<
        Int64 Function(Int64, Pointer<Int64>),
        int Function(int, Pointer<Int64>)
      >('constructorFailure');
  late final recoveredCalls = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>(
        'recoveredCalls',
      );
  late final checkedCall = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('checkedCall');
  late final checkedDouble = _library
      .lookupFunction<Double Function(Double), double Function(double)>(
        'checkedDouble',
      );

  void close() {
    _library.close();
    _storage.close();
  }
}
