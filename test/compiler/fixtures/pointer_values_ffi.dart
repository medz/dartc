import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';
import 'pointer_values.dart' show EchoNative;

final class PointerValues() {
  final _library = NativeAssets(Target.host()).open('compiler/pointer_values');

  late final values = _library
      .lookupFunction<
        Int64 Function(Pointer<Int64>, Int64),
        int Function(Pointer<Int64>, int)
      >('pointerValues');
  late final persistent = _library
      .lookupFunction<
        Int64 Function(Int64, Int64, Int64),
        int Function(int, int, int)
      >('persistentPointer');

  late final casts = _library
      .lookupFunction<
        Int64 Function(Pointer<Void>, Int64),
        int Function(Pointer<Void>, int)
      >('pointerCasts');
  late final scalars = _library
      .lookupFunction<
        Int64 Function(Int64, Int64, Double, Double),
        int Function(int, int, double, double)
      >('scalarIdentity');
  late final indirect = _library
      .lookupFunction<
        Int64 Function(
          Pointer<NativeFunction<EchoNative>>,
          Pointer<Void>,
          Int64,
        ),
        int Function(Pointer<NativeFunction<EchoNative>>, Pointer<Void>, int)
      >('indirectPointer');

  void close() => _library.close();
}
