import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

final class AddressLibrary(String asset) {
  final _library = NativeAssets(Target.host()).open('linker/$asset');

  late final call = _library.lookupFunction<Int64 Function(), int Function()>(
    'forward',
  );
  late final read = _library.lookupFunction<Int64 Function(), int Function()>(
    'read_state',
  );
  late final write = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('write_state');

  Pointer<Int64> address(String name) => _library
      .lookupFunction<Pointer<Int64> Function(), Pointer<Int64> Function()>(
        'address_$name',
      )();

  Pointer<Int64> symbol(String name) => _library.lookup('dartc_address_$name');

  Pointer<Pointer<Int64>> table(String name) =>
      _library.lookup('dartc_address_$name');

  void close() => _library.close();
}
