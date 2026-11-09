import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

final class LinkedCalls() {
  final _library = NativeAssets(Target.host()).open('linker/calls');
  late final forward = _library
      .lookupFunction<Int64 Function(), int Function()>('forward');

  bool hasSymbol(String name) => _library.providesSymbol(name);
  void close() => _library.close();
}
