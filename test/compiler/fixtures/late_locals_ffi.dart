import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

final class LateLocals() {
  final _library = NativeAssets(Target.host()).open('compiler/late_locals');

  late final call = _library
      .lookupFunction<Int64 Function(Int64, Int64), int Function(int, int)>(
        'lateLocals',
      );

  void close() => _library.close();
}
