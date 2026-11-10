import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

final class TypeChecks() {
  final _library = NativeAssets(Target.host()).open('compiler/type_checks');
  final _storage = NativeAssets(Target.host()).open('compiler/pointer_storage');
  late final effects = _storage.lookup<Int64>('counter');

  late final classify = _library
      .lookupFunction<
        Int64 Function(Int64, Int64, Int64),
        int Function(int, int, int)
      >('classify');
  late final promoted = _library
      .lookupFunction<Int64 Function(Int64, Int64), int Function(int, int)>(
        'promoted',
      );
  late final caught = _library
      .lookupFunction<
        Int64 Function(Int64, Int64, Int64),
        int Function(int, int, int)
      >('caught');
  late final castInteger = _library
      .lookupFunction<
        Int64 Function(Int64, Int64, Int64),
        int Function(int, int, int)
      >('castInteger');
  late final castDouble = _library
      .lookupFunction<
        Double Function(Int64, Int64, Int64),
        double Function(int, int, int)
      >('castDouble');
  late final castKinds = _library
      .lookupFunction<
        Int64 Function(Int64, Int64, Int64),
        int Function(int, int, int)
      >('castKinds');
  late final castCleanup = _library
      .lookupFunction<
        Int64 Function(Int64, Int64, Pointer<Int64>),
        int Function(int, int, Pointer<Int64>)
      >('castCleanup');
  late final dynamicThrow = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('dynamicThrow');
  late final castFloating = _library
      .lookupFunction<Double Function(Double), double Function(double)>(
        'castFloating',
      );

  void close() {
    _library.close();
    _storage.close();
  }
}
