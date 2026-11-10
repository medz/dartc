import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

final class TypeChecks() {
  final _library = NativeAssets(Target.host()).open('compiler/type_checks');

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

  void close() => _library.close();
}
