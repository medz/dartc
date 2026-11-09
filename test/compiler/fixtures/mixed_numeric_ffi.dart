import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

final class NumericLibrary() {
  final _library = NativeAssets(Target.host()).open('compiler/mixed_numeric');
  final _storage = NativeAssets(Target.host()).open('compiler/numeric_storage');
  late final memory = _storage.lookup<Int64>('counter');
  late final binary = [
    for (final name in ['add', 'subtract', 'multiply', 'divide'])
      _library.lookupFunction<
        Double Function(Int64, Double),
        double Function(int, double)
      >(name),
  ];
  late final reverseBinary = [
    for (final name in [
      'reverseAdd',
      'reverseSubtract',
      'reverseMultiply',
      'reverseDivide',
    ])
      _library.lookupFunction<
        Double Function(Double, Int64),
        double Function(double, int)
      >(name),
  ];
  late final divideInts = _library
      .lookupFunction<Double Function(Int64, Int64), double Function(int, int)>(
        'divideInts',
      );
  late final converted = _library
      .lookupFunction<Double Function(Int64), double Function(int)>(
        'converted',
      );
  late final doubleIdentity = _library
      .lookupFunction<Double Function(Double), double Function(double)>(
        'doubleIdentity',
      );
  late final comparisons = _library
      .lookupFunction<Int64 Function(Int64, Double), int Function(int, double)>(
        'comparisons',
      );
  late final reverseComparisons = _library
      .lookupFunction<Int64 Function(Double, Int64), int Function(double, int)>(
        'reverseComparisons',
      );
  late final constantComparison = _library
      .lookupFunction<Int64 Function(), int Function()>('constantComparison');
  late final pressure = _library
      .lookupFunction<
        Double Function(Int64, Double),
        double Function(int, double)
      >('pressure');
  late final loop = _library
      .lookupFunction<
        Double Function(Int64, Double),
        double Function(int, double)
      >('loop');
  late final orderedComparison = _library
      .lookupFunction<
        Int64 Function(Pointer<Int64>, Double),
        int Function(Pointer<Int64>, double)
      >('orderedComparison');

  void close() {
    _library.close();
    _storage.close();
  }
}
