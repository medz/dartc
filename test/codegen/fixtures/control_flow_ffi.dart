import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

final class ControlFlowGraphs() {
  final _library = NativeAssets(Target.host()).open('codegen/control_flow');
  late final sameTarget = _library
      .lookupFunction<Int64 Function(Int64, Int64), int Function(int, int)>(
        'same_target',
      );
  late final scrambled = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('scrambled');
  late final unusedResult = _library
      .lookupFunction<
        Int64 Function(Int64, Int64, Int64, Int64, Int64, Int64),
        int Function(int, int, int, int, int, int)
      >('unused_result');

  void close() => _library.close();
}
