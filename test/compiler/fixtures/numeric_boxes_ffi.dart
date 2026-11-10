import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

final class NumericBoxes() {
  final _library = NativeAssets(Target.host()).open('compiler/numeric_boxes');
  late final heldInteger = _library
      .lookupFunction<Int64 Function(Int64, Int64), int Function(int, int)>(
        'heldInteger',
      );
  late final heldFloating = _library
      .lookupFunction<
        Double Function(Double, Int64),
        double Function(double, int)
      >('heldFloating');
  late final optional = _library
      .lookupFunction<Int64 Function(Int64, Int64), int Function(int, int)>(
        'optional',
      );

  void close() => _library.close();
}
