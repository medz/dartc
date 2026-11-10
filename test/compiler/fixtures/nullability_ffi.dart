import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

final class Nullability() {
  final _library = NativeAssets(Target.host()).open('compiler/nullability');

  late final integer = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('integer');
  late final floating = _library
      .lookupFunction<Double Function(Int64), double Function(int)>('floating');
  late final boolean = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('boolean');
  late final predicates = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('predicates');
  late final coalescing = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('coalescing');
  late final shortCircuit = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('shortCircuit');
  late final rotate = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('rotate');

  void close() => _library.close();
}
