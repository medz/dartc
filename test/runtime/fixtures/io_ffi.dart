import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

final class IoLibrary(String name) {
  final _library = NativeAssets(Target.host()).open('runtime/$name');
  final _system = DynamicLibrary.process();

  late final bytes = _library.lookup<Uint8>('io_bytes');
  late final state = _library.lookup<Int64>('io_state');
  late final write = _library
      .lookupFunction<
        Int64 Function(Int64, Pointer<Uint8>, Int64),
        int Function(int, Pointer<Uint8>, int)
      >('writeDescriptor');
  late final pipe = _system
      .lookupFunction<
        Int32 Function(Pointer<Int32>),
        int Function(Pointer<Int32>)
      >('pipe');
  late final closeDescriptor = _system
      .lookupFunction<Int32 Function(Int32), int Function(int)>('close');
  late final read = _system
      .lookupFunction<
        Int64 Function(Int32, Pointer<Uint8>, Uint64),
        int Function(int, Pointer<Uint8>, int)
      >('read');

  void close() => _library.close();
}
