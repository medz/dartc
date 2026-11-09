import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

const nativeImportSymbols = {
  'math:first': {'step': 'increment', 'pointer': 'opaque'},
  'math:second': {'step': 'decrement'},
};

final class NativeImports() {
  final _library = NativeAssets(Target.host()).open('compiler/native_imports');

  late final run = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('runImports');
  late final pointer = _library
      .lookupFunction<
        Int64 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('pointerResult');

  void close() => _library.close();
}
