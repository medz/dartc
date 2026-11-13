import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

final class MathLibrary() {
  final _library = NativeAssets(Target.host()).open('compiler/math');
  final _storage = NativeAssets(Target.host()).open('compiler/math_storage');

  late final memory = _storage.lookup<Double>('counter');
  late final squareRoot = _library
      .lookupFunction<Double Function(Double), double Function(double)>(
        'squareRoot',
      );
  late final integerRoot = _library
      .lookupFunction<Double Function(Int64), double Function(int)>(
        'integerRoot',
      );
  late final liveInput = _library
      .lookupFunction<Double Function(Double), double Function(double)>(
        'liveInput',
      );
  late final nested = _library
      .lookupFunction<Double Function(Double), double Function(double)>(
        'nested',
      );
  late final iterate = _library
      .lookupFunction<
        Double Function(Int64, Double),
        double Function(int, double)
      >('iterate');
  late final ordered = _library
      .lookupFunction<
        Double Function(Pointer<Double>),
        double Function(Pointer<Double>)
      >('ordered');
  late final shadowed = _library
      .lookupFunction<Double Function(Double), double Function(double)>(
        'shadowed',
      );

  late final boxedRoot = _library
      .lookupFunction<
        Double Function(Double, Int64, Int32),
        double Function(double, int, int)
      >('boxedRoot');
  late final rejectedRoot = _library
      .lookupFunction<Int32 Function(Int32), int Function(int)>('rejectedRoot');

  late final floatingMath = _library
      .lookupFunction<
        Double Function(Int32, Double, Double),
        double Function(int, double, double)
      >('floatingMath');
  late final integerPower = _library
      .lookupFunction<Int64 Function(Int64, Int64), int Function(int, int)>(
        'integerPower',
      );
  late final indirectMath = _library
      .lookupFunction<
        Double Function(Double, Int64, Int32),
        double Function(double, int, int)
      >('indirectMath');
  late final composed = _library
      .lookupFunction<
        Double Function(Double, Double),
        double Function(double, double)
      >('composed');
  late final orderedPower = _library
      .lookupFunction<
        Double Function(Pointer<Double>),
        double Function(Pointer<Double>)
      >('orderedPower');
  late final rejectedMath = _library
      .lookupFunction<Int32 Function(Int32), int Function(int)>('rejectedMath');

  void close() {
    _library.close();
    _storage.close();
  }
}
