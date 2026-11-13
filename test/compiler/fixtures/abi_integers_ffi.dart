import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';
import 'abi_integers.dart';

final class AbiIntegers() {
  final _library = NativeAssets(Target.host()).open('compiler/abi_integers');
  final _storage = NativeAssets(Target.host())
      .open('compiler/abi_integers_storage');
  late final memory = _storage.lookup<PlatformInt>('counter');
  late final identity = _library.lookupFunction<Callback, int Function(int)>(
    'identity',
  );
  late final callback = _library.lookup<NativeFunction<Callback>>('identity');
  late final character = _library
      .lookupFunction<Char Function(Char), int Function(int)>('character');
  late final integerSize = _library
      .lookupFunction<Size Function(), int Function()>('integerSize');
  late final checkCurrentAbi = _library
      .lookupFunction<Bool Function(Int32, Int32), bool Function(int, int)>(
        'checkCurrentAbi',
      );
  late final stateSize = _library
      .lookupFunction<Size Function(), int Function()>('stateSize');
  late final access = _library
      .lookupFunction<
        PlatformInt Function(Pointer<PlatformInt>, IntPtr, Int64),
        int Function(Pointer<PlatformInt>, int, int)
      >('access');
  late final offset = _library
      .lookupFunction<
        Pointer<PlatformInt> Function(Pointer<PlatformInt>, IntPtr),
        Pointer<PlatformInt> Function(Pointer<PlatformInt>, int)
      >('offset');
  late final update = _library
      .lookupFunction<
        Int64 Function(Pointer<IntegerState>, Int64),
        int Function(Pointer<IntegerState>, int)
      >('update');
  late final arrayList = _library
      .lookupFunction<
        Int64 Function(Pointer<IntegerState>, Int64),
        int Function(Pointer<IntegerState>, int)
      >('arrayList');
  late final arrayListFailure = _library
      .lookupFunction<
        Bool Function(Pointer<IntegerState>, Int32),
        bool Function(Pointer<IntegerState>, int)
      >('arrayListFailure');
  late final retainArrayList = _library
      .lookupFunction<Void Function(Int64), void Function(int)>(
        'retainArrayList',
      );
  late final readRetainedArrayList = _library
      .lookupFunction<Int64 Function(Int32), int Function(int)>(
        'readRetainedArrayList',
      );
  late final invoke = _library
      .lookupFunction<
        Int64 Function(Pointer<NativeFunction<Callback>>, Int64),
        int Function(Pointer<NativeFunction<Callback>>, int)
      >('invoke');
  late final stack = _library
      .lookupFunction<
        PlatformInt Function(
          PlatformInt,
          PlatformInt,
          PlatformInt,
          PlatformInt,
          PlatformInt,
          PlatformInt,
          PlatformInt,
          PlatformInt,
          PlatformInt,
          PlatformInt,
        ),
        int Function(int, int, int, int, int, int, int, int, int, int)
      >('stack');

  void close() {
    _library.close();
    _storage.close();
  }
}
