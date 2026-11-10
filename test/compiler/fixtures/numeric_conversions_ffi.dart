import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

final class NumericConversions() {
  final _library = NativeAssets(Target.host())
      .open('compiler/numeric_conversions');
  late final doubles = [
    for (final name in ['convertDouble', 'boxedDouble'])
      _library.lookupFunction<
        Int64 Function(Double, Int64),
        int Function(double, int)
      >(name),
  ];
  late final integers = [
    for (final name in ['convertInt', 'boxedInt'])
      _library
          .lookupFunction<Int64 Function(Int64, Int64), int Function(int, int)>(
            name,
          ),
  ];
  late final failure = _library
      .lookupFunction<
        Int64 Function(Double, Int64, Int64),
        int Function(double, int, int)
      >('conversionFailure');
  late final savedMessage = _library
      .lookupFunction<Int64 Function(Double, Int64), int Function(double, int)>(
        'savedMessage',
      );

  late final checkedNonnegative = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>(
        'checkedNonnegative',
      );

  late final floatingRounds = [
    for (final name in ['roundDoubleToDouble', 'roundBoxedDouble'])
      _library.lookupFunction<
        Double Function(Double, Int64),
        double Function(double, int)
      >(name),
  ];
  late final integerRounds = [
    for (final name in ['roundIntToDouble', 'roundBoxedInt'])
      _library.lookupFunction<
        Double Function(Int64, Int64),
        double Function(int, int)
      >(name),
  ];
  late final roundingEffects = _library
      .lookupFunction<Int64 Function(Double, Int64), int Function(double, int)>(
        'roundingEffects',
      );

  late final truncateDivide = _library
      .lookupFunction<
        Int64 Function(Double, Double, Int64, Int64, Int64),
        int Function(double, double, int, int, int)
      >('truncateDivide');
  late final quotientFailure = _library
      .lookupFunction<
        Int64 Function(Double, Double, Int64),
        int Function(double, double, int)
      >('quotientFailure');

  late final integerQuotientFailure = _library
      .lookupFunction<Int64 Function(Int64, Int64), int Function(int, int)>(
        'integerQuotientFailure',
      );

  void close() => _library.close();
}
