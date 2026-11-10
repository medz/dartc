import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

final class ClassTypes() {
  final _library = NativeAssets(Target.host()).open('compiler/class_types');
  late final call = _library
      .lookupFunction<
        Int64 Function(Int64, Int64, Double, Int64),
        int Function(int, int, double, int)
      >('classTypes');

  void close() => _library.close();
}
