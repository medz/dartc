import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';
import 'pointers.dart' show MixedNative, MixedDart;

final class PointerLibrary() {
  final _library = NativeAssets(Target.host()).open('compiler/pointers');
  final _storage = NativeAssets(Target.host()).open('compiler/pointer_storage');
  late final memory = _storage.lookup<Int64>('counter');
  late final fromAddress = _library
      .lookupFunction<
        Pointer<Int64> Function(Int64),
        Pointer<Int64> Function(int)
      >('fromAddress');
  late final address = _library
      .lookupFunction<
        Int64 Function(Pointer<Int64>),
        int Function(Pointer<Int64>)
      >('address');
  late final read = _library
      .lookupFunction<
        Int64 Function(Pointer<Int64>),
        int Function(Pointer<Int64>)
      >('read');
  late final write = _library
      .lookupFunction<
        Void Function(Pointer<Int64>, Int64),
        void Function(Pointer<Int64>, int)
      >('write');
  late final equal = _library
      .lookupFunction<
        Int64 Function(Pointer<Int64>, Pointer<Int64>),
        int Function(Pointer<Int64>, Pointer<Int64>)
      >('equal');
  late final rotate = _library
      .lookupFunction<
        Pointer<Int64> Function(Pointer<Int64>, Pointer<Int64>, Int64),
        Pointer<Int64> Function(Pointer<Int64>, Pointer<Int64>, int)
      >('rotate');
  late final update = _library
      .lookupFunction<
        Int64 Function(Pointer<Int64>, Pointer<Int64>),
        int Function(Pointer<Int64>, Pointer<Int64>)
      >('update');
  late final mixed = _library.lookupFunction<MixedNative, MixedDart>('mixed');
  late final forward = _library.lookupFunction<MixedNative, MixedDart>(
    'forward',
  );
  late final declaredMember = _library
      .lookupFunction<
        Int64 Function(Pointer<Int64>),
        int Function(Pointer<Int64>)
      >('declaredMember');

  void close() {
    _library.close();
    _storage.close();
  }
}
