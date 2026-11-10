import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

final class TypeArguments() {
  final _library = NativeAssets(Target.host()).open('compiler/type_arguments');
  late final subtypeStress = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>(
        'subtypeStress',
      );
  late final openChecks = _library
      .lookupFunction<
        Int64 Function(Int64, Int64, Int64),
        int Function(int, int, int)
      >('openChecks');
  late final subtypeShapes = _library
      .lookupFunction<Int64 Function(Int64, Int64), int Function(int, int)>(
        'subtypeShapes',
      );
  late final wordCast = _library
      .lookupFunction<
        Int64 Function(Int64, Int64, Int64),
        int Function(int, int, int)
      >('wordCast');
  late final doubleCast = _library
      .lookupFunction<
        Double Function(Double, Int64),
        double Function(double, int)
      >('doubleCast');
  late final types = _library
      .lookupFunction<
        Int64 Function(Int64, Int64, Int64),
        int Function(int, int, int)
      >('types');
  late final stack = _library
      .lookupFunction<
        Int64 Function(Int64, Int64, Double, Int64, Int64),
        int Function(int, int, double, int, int)
      >('stack');
  late final integer = _library
      .lookupFunction<Int64 Function(Int64, Int64), int Function(int, int)>(
        'integer',
      );
  late final structures = _library
      .lookupFunction<Int64 Function(Int64, Int64), int Function(int, int)>(
        'structures',
      );
  late final bounds = _library
      .lookupFunction<Int64 Function(Int64, Int64), int Function(int, int)>(
        'bounds',
      );
  late final runtimeTypes = _library
      .lookupFunction<Int64 Function(Int64, Int64), int Function(int, int)>(
        'runtimeTypes',
      );
  late final floating = _library
      .lookupFunction<
        Double Function(Double, Int64),
        double Function(double, int)
      >('floating');

  void close() => _library.close();
}
