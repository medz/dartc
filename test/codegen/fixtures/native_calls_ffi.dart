import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../compiler/fixtures/native_floats.dart' show MixedNative, MixedDart;
import '../../support/native_assets.dart';

final class NativeCalls() {
  final _library = NativeAssets(Target.host()).open('codegen/native_calls');
  late final memory = _library.lookup<Int64>('memory');
  int Function(int) integer(String name) =>
      _library.lookupFunction<Int64 Function(Int64), int Function(int)>(name);
  late final argumentFloat = _library
      .lookupFunction<Double Function(Double), double Function(double)>(
        'argumentFloat',
      );
  late final resultFloat = _library
      .lookupFunction<Double Function(Double), double Function(double)>(
        'resultFloat',
      );
  late final pointer = _library
      .lookupFunction<
        Pointer<Int64> Function(Pointer<Int64>),
        Pointer<Int64> Function(Pointer<Int64>)
      >('pointer');
  late final write = _library
      .lookupFunction<
        Int64 Function(Pointer<Int64>, Int64),
        int Function(Pointer<Int64>, int)
      >('write');
  late final mixed = _library
      .lookupFunction<
        Double Function(Pointer<Double>, Int64, Double),
        double Function(Pointer<Double>, int, double)
      >('mixed');
  late final providedMixed = _library.lookupFunction<MixedNative, MixedDart>(
    'provided_mixed',
  );

  void close() => _library.close();
}
