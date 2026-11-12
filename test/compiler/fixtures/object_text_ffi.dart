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

  late final _type = _library
      .lookupFunction<
        Int32 Function(Int32, Pointer<Uint16>, IntPtr),
        int Function(int, Pointer<Uint16>, int)
      >('typeBuffer');

  late final _dispatch = _library
      .lookupFunction<
        Int32 Function(Int32, Pointer<Uint16>, IntPtr),
        int Function(int, Pointer<Uint16>, int)
      >('dispatchBuffer');

  String dispatchText(int mode) => _read(_dispatch(mode, _output, 2048));

  String typeText(int mode) => _read(_type(mode, _output, 2048));

  String collection(int mode) => _read(_collection(mode, _output, 2048));

  String format(double value, int mode, int digits) {
    final count = _format(value, mode, digits, _output, 2048);
    if (count == -1) throw RangeError('Native precision');
    return _read(count);
  }

  String _read(int count) {
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
