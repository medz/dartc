import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

final class Strings() {
  final _library = NativeAssets(Target.host()).open('compiler/strings');
  late final length = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('stringLength');
  late final read = _library
      .lookupFunction<
        Int64 Function(Int64, Int64, Int64, Int64),
        int Function(int, int, int, int)
      >('stringRead');
  late final failure = _library
      .lookupFunction<
        Int64 Function(Int64, Int64, Int64),
        int Function(int, int, int)
      >('stringFailure');

  void close() => _library.close();
}
