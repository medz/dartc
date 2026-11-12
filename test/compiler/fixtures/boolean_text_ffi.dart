import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

final class BooleanText() {
  static const _capacity = 128;
  final _library = NativeAssets(Target.host()).open('compiler/boolean_text');
  final _memory = DynamicLibrary.process()
      .lookupFunction<
        Pointer<Void> Function(IntPtr),
        Pointer<Void> Function(int)
      >('malloc')(_capacity * 2 + 1);
  this {
    if (_memory.address == 0) throw StateError('Test allocation failed');
  }
  late final _parse = _library
      .lookupFunction<
        Int8 Function(Pointer<Uint16>, IntPtr, Bool, Int32, Pointer<Bool>),
        int Function(Pointer<Uint16>, int, bool, int, Pointer<Bool>)
      >('parseBuffer');

  (int, bool?) parse(String source, bool caseSensitive, int mode) {
    if (source.length > _capacity) throw ArgumentError('Test input too long');
    final input = _memory.cast<Uint16>();
    input.asTypedList(_capacity).setRange(0, source.length, source.codeUnits);
    final output = (input + _capacity).cast<Bool>();
    final status = _parse(input, source.length, caseSensitive, mode, output);
    return (status, status == 0 ? output.value : null);
  }

  void close() {
    _library.close();
    DynamicLibrary.process().lookupFunction<
      Void Function(Pointer<Void>),
      void Function(Pointer<Void>)
    >('free')(_memory);
  }
}
