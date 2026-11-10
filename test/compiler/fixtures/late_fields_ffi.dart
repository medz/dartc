import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

final class LateFields() {
  final _library = NativeAssets(Target.host()).open('compiler/late_fields');

  late final isolation = _library
      .lookupFunction<Int64 Function(), int Function()>('isolation');

  late final nullableBinding = _library
      .lookupFunction<Int64 Function(), int Function()>('nullableBinding');

  late final initialization = _library
      .lookupFunction<Int64 Function(), int Function()>('initialization');

  late final writeOrdering = _library
      .lookupFunction<Int64 Function(), int Function()>('writeOrdering');

  late final genericEnvironment = _library
      .lookupFunction<Int64 Function(), int Function()>('genericEnvironment');

  late final genericFinalSafety = _library
      .lookupFunction<Int64 Function(), int Function()>('genericFinalSafety');

  late final references = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('references');

  void close() => _library.close();
}
