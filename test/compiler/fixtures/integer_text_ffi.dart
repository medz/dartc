import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

final class IntegerText() {
  static const _capacity = 2048;
  final _library = NativeAssets(Target.host()).open('compiler/integer_text');
  final _memory = DynamicLibrary.process()
      .lookupFunction<
        Pointer<Void> Function(IntPtr),
        Pointer<Void> Function(int)
      >('malloc')(_capacity * 2 + 8);
  this {
    if (_memory.address == 0) throw StateError('Test allocation failed');
  }
  late final _parse = _library
      .lookupFunction<
        Int32 Function(Pointer<Uint16>, IntPtr, Int32, Int32, Pointer<Int64>),
        int Function(Pointer<Uint16>, int, int, int, Pointer<Int64>)
      >('parseBuffer');
  late final _format = _library
      .lookupFunction<
        Int32 Function(Int64, Int32, Int32, Pointer<Uint16>, IntPtr),
        int Function(int, int, int, Pointer<Uint16>, int)
      >('formatBuffer');

  (int, int?) parse(String source, int? radix, int mode) {
    if (source.length > _capacity) throw ArgumentError('Test input too long');
    final input = _memory.cast<Uint16>();
    input.asTypedList(_capacity).setRange(0, source.length, source.codeUnits);
    final output = (input + _capacity).cast<Int64>();
    final status = _parse(input, source.length, radix ?? 0, mode, output);
    return (status, status == 0 ? output.value : null);
  }

  String format(int value, int radix, int mode) {
    final output = _memory.cast<Uint16>();
    final length = _format(value, radix, mode, output, _capacity);
    if (length == -1) throw RangeError('Native radix');
    if (length < 0) throw StateError('Test output too long');
    return String.fromCharCodes(output.asTypedList(length));
  }

  void close() {
    _library.close();
    DynamicLibrary.process().lookupFunction<
      Void Function(Pointer<Void>),
      void Function(Pointer<Void>)
    >('free')(_memory);
  }
}
