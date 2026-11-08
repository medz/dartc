import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../native_assets.dart';

final class Aliases() {
  final _library = NativeAssets(Target.host()).open('codegen/aliases');

  late final add = _library
      .lookupFunction<Int64 Function(Int64, Int64), int Function(int, int)>(
        'alias_add',
      );
  late final subtract = _library
      .lookupFunction<Int64 Function(Int64, Int64), int Function(int, int)>(
        'alias_subtract',
      );

  void close() => _library.close();
}
