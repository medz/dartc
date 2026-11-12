import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

final class NativeFinalizers() {
  final _assets = NativeAssets(Target.host());
  late final _provider = _assets.open('compiler/native_finalizer_callback');
  late final _library = _assets.open('compiler/native_finalizers');
  late final state = _provider.lookup<Int64>('resource_state');
  var _unloaded = false;
  this {
    state.value = 0;
    final callback = _provider.lookup<NativeFinalizerFunction>(
      'resource_released',
    );
    _library.lookupFunction<
      Void Function(Pointer<NativeFinalizerFunction>),
      void Function(Pointer<NativeFinalizerFunction>)
    >('configure')(callback);
  }
  late final lifetimes = _library
      .lookupFunction<
        Int64 Function(Pointer<Int64>, Int32),
        int Function(Pointer<Int64>, int)
      >('lifetimes');
  late final collect = _library
      .lookupFunction<
        Int64 Function(Pointer<Int64>),
        int Function(Pointer<Int64>)
      >('collect');
  late final callClosure = _library
      .lookupFunction<Int64 Function(), int Function()>('callClosure');
  late final releaseClosure = _library
      .lookupFunction<Void Function(), void Function()>('releaseClosure');
  late final attach = _library
      .lookupFunction<
        Void Function(Pointer<Int64>, Int32),
        void Function(Pointer<Int64>, int)
      >('attach');
  late final invalidSize = _library
      .lookupFunction<
        Bool Function(Pointer<Int64>, Int64),
        bool Function(Pointer<Int64>, int)
      >('invalidSize');
  late final pointerViews = _library
      .lookupFunction<
        Int64 Function(Pointer<Int64>, Int32),
        int Function(Pointer<Int64>, int)
      >('pointerViews');

  int unload() {
    if (!_unloaded) {
      _library.close();
      _unloaded = true;
    }
    return state.value;
  }

  void close() {
    unload();
    _provider.close();
  }
}
