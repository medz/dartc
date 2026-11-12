import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

final class ObjectText() {
  final _library = NativeAssets(Target.host()).open('compiler/object_text');
  final _output = DynamicLibrary.process()
      .lookupFunction<
        Pointer<Uint16> Function(IntPtr),
        Pointer<Uint16> Function(int)
      >('malloc')(4096);
  this {
    if (_output.address == 0) throw StateError('Test allocation failed');
  }
  late final _format = _library
      .lookupFunction<
        Int32 Function(Double, Int32, Int32, Pointer<Uint16>, IntPtr),
        int Function(double, int, int, Pointer<Uint16>, int)
      >('formatBuffer');
  late final _collection = _library
      .lookupFunction<
        Int32 Function(Int32, Pointer<Uint16>, IntPtr),
        int Function(int, Pointer<Uint16>, int)
      >('collectionBuffer');

  String collection(int mode) {
    final count = _collection(mode, _output, 2048);
    if (count < 0) throw StateError('Test output too long');
    return String.fromCharCodes(_output.asTypedList(count));
  }

  String format(double value, int mode, int digits) {
    final count = _format(value, mode, digits, _output, 2048);
    if (count == -1) throw RangeError('Native precision');
    if (count < 0) throw StateError('Test output too long');
    return String.fromCharCodes(_output.asTypedList(count));
  }

  void close() {
    _library.close();
    DynamicLibrary.process().lookupFunction<
      Void Function(Pointer<Void>),
      void Function(Pointer<Void>)
    >('free')(_output.cast());
  }
}
