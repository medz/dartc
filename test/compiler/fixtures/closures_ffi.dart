import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

final class Closures() {
  final _library = NativeAssets(Target.host()).open('compiler/closures');

  late final collect = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('collect');
  late final counter = _library
      .lookupFunction<Int64 Function(Int64, Int64), int Function(int, int)>(
        'counter',
      );
  late final nested = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('nested');
  late final recursive = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('recursive');
  late final iteration = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('iteration');
  late final captures = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('captures');
  late final afterExit = _library
      .lookupFunction<Int64 Function(Int64, Int64), int Function(int, int)>(
        'afterExit',
      );
  late final invocationFailure = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>(
        'invocationFailure',
      );
  late final generic = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('generic');
  late final defaults = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('defaults');

  void close() => _library.close();
}
