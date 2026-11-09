import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

final class DataLibrary() {
  final _library = NativeAssets(Target.host()).open('linker/data');
  late final readConstant = _library
      .lookupFunction<Int64 Function(), int Function()>('read_constant');
  late final readLocal = _library
      .lookupFunction<Int64 Function(), int Function()>('read_local');
  late final updateState = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('update_state');
  late final updateCounter = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>(
        'update_counter',
      );
  late final state = _library.lookup<Int64>('state');
  late final counter = _library.lookup<Int64>('counter');

  bool contains(String name) => _library.providesSymbol(name);
  void close() => _library.close();
}

final class StorageLibrary() {
  final _library = NativeAssets(Target.host()).open('linker/storage');
  late final state = _library.lookup<Int64>('state');
  late final counter = _library.lookup<Int64>('counter');

  void close() => _library.close();
}
