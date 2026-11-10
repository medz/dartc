import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

final class TypeArguments() {
  final _library = NativeAssets(Target.host()).open('compiler/type_arguments');
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
  late final floating = _library
      .lookupFunction<
        Double Function(Double, Int64),
        double Function(double, int)
      >('floating');

  void close() => _library.close();
}
