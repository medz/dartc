import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

final class NumericMethods() {
  final _library = NativeAssets(Target.host()).open('compiler/numeric_methods');
  late final floating = _library
      .lookupFunction<
        Double Function(Double, Int64),
        double Function(double, int)
      >('floating');
  late final integer = _library
      .lookupFunction<Double Function(Int64, Int64), double Function(int, int)>(
        'integer',
      );
  late final order = _library
      .lookupFunction<
        Int64 Function(Double, Double, Int64, Int64),
        int Function(double, double, int, int)
      >('order');
  late final clamp = _library
      .lookupFunction<
        Double Function(Double, Double, Double, Int64),
        double Function(double, double, double, int)
      >('clamp');

  late final arithmetic = _library
      .lookupFunction<
        Double Function(Int64, Double, Int64, Int64),
        double Function(int, double, int, int)
      >('arithmetic');

  void close() => _library.close();
}
