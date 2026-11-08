import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../native_assets.dart';

final class Values() {
  final _library = NativeAssets(Target.host()).open('linker/values');

  late final first = _library.lookupFunction<Int64 Function(), int Function()>(
    'first',
  );
  late final second = _library.lookupFunction<Int64 Function(), int Function()>(
    'second',
  );

  void close() => _library.close();
}

final class Symbols() {
  final _library = NativeAssets(Target.host()).open('linker/symbols');

  int call(String name) =>
      _library.lookupFunction<Int64 Function(), int Function()>(name)();

  bool contains(String name) => _library.providesSymbol(name);

  void close() => _library.close();
}
