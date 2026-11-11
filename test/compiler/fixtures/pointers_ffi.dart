import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';
import 'pointers.dart' show MixedNative, MixedDart, ReadPointer;

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
  late final exchangePointer = _library
      .lookupFunction<
        Pointer<Int64> Function(Pointer<Pointer<Int64>>, Int64, Pointer<Int64>),
        Pointer<Int64> Function(Pointer<Pointer<Int64>>, int, Pointer<Int64>)
      >('exchangePointer');
  late final swapSlots = _library
      .lookupFunction<
        Pointer<Int64> Function(Pointer<Pointer<Int64>>, Int64),
        Pointer<Int64> Function(Pointer<Pointer<Int64>>, int)
      >('swapSlots');
  late final offsetSlots = _library
      .lookupFunction<
        Pointer<Pointer<Int64>> Function(Pointer<Pointer<Int64>>, Int64, Int64),
        Pointer<Pointer<Int64>> Function(Pointer<Pointer<Int64>>, int, int)
      >('offsetSlots');
  late final readThroughSlot = _library
      .lookupFunction<
        Int64 Function(Pointer<ReadPointer>, Pointer<Int64>),
        int Function(Pointer<ReadPointer>, Pointer<Int64>)
      >('readThroughSlot');
  late final readPointer = _library
      .lookup<NativeFunction<Int64 Function(Pointer<Int64>)>>('read');
  late final retainSlot = _library
      .lookupFunction<
        Pointer<Int64> Function(Pointer<Pointer<Int64>>, Int64),
        Pointer<Int64> Function(Pointer<Pointer<Int64>>, int)
      >('retainSlot');

  void close() {
    _library.close();
    _storage.close();
  }
}
