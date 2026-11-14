import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

final class ExceptionCalls() {
  final _library = NativeAssets(Target.host()).open('codegen/exceptions');
  late final table = _library.lookup<Uint64>('exception_roots');
  late final probe = _library.lookup<Void>('roots_probe');
  late final plain = _library
      .lookupFunction<
        Int64 Function(Int64, Int64, Int64),
        int Function(int, int, int)
      >('plain');
  late final error = _library
      .lookupFunction<
        Int64 Function(Int64, Int64, Int64),
        int Function(int, int, int)
      >('error');

  late final local = _library.lookupFunction<Int64 Function(), int Function()>(
    'local',
  );

  void close() => _library.close();
}
