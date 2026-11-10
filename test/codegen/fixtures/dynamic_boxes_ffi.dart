import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

final class DynamicBoxes() {
  final _library = NativeAssets(Target.host()).open('codegen/dynamic_boxes');
  late final collect = _library
      .lookupFunction<Int64 Function(Int64, Int64), int Function(int, int)>(
        'gc_arguments',
      );
  late final checkedInteger = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>(
        'checked_integer',
      );
  late final checkedFloating = _library
      .lookupFunction<Double Function(Double), double Function(double)>(
        'checked_floating',
      );

  int integer(String operation, int value) =>
      _library.lookupFunction<Int64 Function(Int64), int Function(int)>(
        'read_integer_$operation',
      )(value);
  double floating(String operation, double value) =>
      _library.lookupFunction<Double Function(Double), double Function(double)>(
        'read_floating_$operation',
      )(value);

  void close() => _library.close();
}
