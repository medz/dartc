import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

final class ArchiveCalls() {
  final _library = NativeAssets(Target.host()).open('linker/archive_calls');
  late final forward = _library
      .lookupFunction<Int64 Function(), int Function()>('forward');
  late final callback = _library
      .lookupFunction<Int64 Function(), int Function()>('archive_callback');

  bool contains(String name) => _library.providesSymbol(name);
  void close() => _library.close();
}
