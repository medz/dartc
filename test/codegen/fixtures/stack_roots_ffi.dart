import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

typedef RootVisitor = Int64 Function(Uint64, Pointer<Uint64>);

final class StackRootCalls() {
  final _library = NativeAssets(Target.host()).open('codegen/stack_roots');
  late final table = _library.lookup<Uint64>('roots_table');
  late final original = _library.lookup<Uint64>('roots_original');
  late final replacement = _library.lookup<Uint64>('roots_replacement');
  late final probe = _library.lookup<Void>('roots_probe');
  late final run = _library
      .lookupFunction<
        Int64 Function(Int64, Int64, Int64, Int64),
        int Function(int, int, int, int)
      >('roots_run');

  void close() => _library.close();
}
