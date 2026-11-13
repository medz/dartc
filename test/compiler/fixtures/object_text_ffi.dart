import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';
import 'object_text.dart' show ParsedNumber;
import 'core_conversion.dart' show Conversion;

final class ObjectText() {
  final _library = NativeAssets(Target.host()).open('compiler/object_text');
  final _output = DynamicLibrary.process()
      .lookupFunction<
        Pointer<Uint16> Function(IntPtr),
        Pointer<Uint16> Function(int)
      >('malloc')(4096 + sizeOf<ParsedNumber>());
  this {
    if (_output.address == 0) throw StateError('Test allocation failed');
  }
  late final _parse = _library
      .lookupFunction<
        Int32 Function(Pointer<Uint16>, IntPtr, Int32, Pointer<ParsedNumber>),
        int Function(Pointer<Uint16>, int, int, Pointer<ParsedNumber>)
      >('parseBuffer');
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

  late final _conversion = _library
      .lookupFunction<
        Int32 Function(
          Pointer<Uint16>,
          IntPtr,
          Int32,
          IntPtr,
          Pointer<Uint16>,
          IntPtr,
        ),
        int Function(Pointer<Uint16>, int, int, int, Pointer<Uint16>, int)
      >('conversionBuffer');

  String convert(String source, Conversion mode, [int split = 0]) {
    if (source.length > 2048) throw ArgumentError('Test input too long');
    _output.asTypedList(source.length).setAll(0, source.codeUnits);
    return _read(
      _conversion(_output, source.length, mode.index, split, _output, 2048),
    );
  }

  String dispatchText(int mode) => _read(_dispatch(mode, _output, 2048));

  String typeText(int mode) => _read(_type(mode, _output, 2048));

  String collection(int mode) => _read(_collection(mode, _output, 2048));

  (int, num?) parse(String source, int mode) {
    if (source.length > 2048) throw ArgumentError('Test input too long');
    _output.asTypedList(source.length).setAll(0, source.codeUnits);
    final result = (_output + 2048).cast<ParsedNumber>();
    final status = _parse(_output, source.length, mode, result);
    return (
      status,
      switch (status) {
        0 => result.ref.floating,
        1 => result.ref.integer,
        _ => null,
      },
    );
  }

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
