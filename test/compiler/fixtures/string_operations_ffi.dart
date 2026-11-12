import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

final class StringOperations() {
  static const _capacity = 4096;
  final _library = NativeAssets(Target.host())
      .open('compiler/string_operations');
  final _memory = DynamicLibrary.process()
      .lookupFunction<
        Pointer<Void> Function(IntPtr),
        Pointer<Void> Function(int)
      >('malloc')(3 * _capacity * 2)
      .cast<Uint16>();
  this {
    if (_memory.address == 0) throw StateError('Test allocation failed');
  }
  late final _transform = _library
      .lookupFunction<
        Int64 Function(
          Pointer<Uint16>,
          Int64,
          Pointer<Uint16>,
          Int64,
          Int32,
          Int64,
          Int64,
          Pointer<Uint16>,
          Int64,
        ),
        int Function(
          Pointer<Uint16>,
          int,
          Pointer<Uint16>,
          int,
          int,
          int,
          int,
          Pointer<Uint16>,
          int,
        )
      >('transformBuffer');
  late final _copy = _library
      .lookupFunction<
        Int64 Function(Pointer<Uint16>, Int64),
        int Function(Pointer<Uint16>, int)
      >('copySaved');
  late final _inspect = _library
      .lookupFunction<
        Int64 Function(
          Pointer<Uint16>,
          Int64,
          Pointer<Uint16>,
          Int64,
          Int32,
          Int64,
        ),
        int Function(Pointer<Uint16>, int, Pointer<Uint16>, int, int, int)
      >('inspectBuffer');
  void _input(String value, String pattern) {
    if (value.length > _capacity || pattern.length > _capacity) {
      throw ArgumentError('Test input too long');
    }
    _memory.asTypedList(_capacity).setRange(0, value.length, value.codeUnits);
    (_memory + _capacity)
        .asTypedList(_capacity)
        .setRange(0, pattern.length, pattern.codeUnits);
  }

  String transform(
    String value,
    String pattern,
    int mode,
    int first,
    int last,
  ) {
    _input(value, pattern);
    final output = _memory + 2 * _capacity;
    final count = _transform(
      _memory,
      value.length,
      _memory + _capacity,
      pattern.length,
      mode,
      first,
      last,
      output,
      _capacity,
    );
    if (count == -1) throw RangeError('Native range');
    if (count < 0) throw StateError('Test output too long');
    return String.fromCharCodes(output.asTypedList(count));
  }

  String saved() {
    final count = _copy(_memory, _capacity);
    if (count < 0) throw StateError('Test output too long');
    return String.fromCharCodes(_memory.asTypedList(count));
  }

  int inspect(String value, String pattern, int mode, int start) {
    _input(value, pattern);
    return _inspect(
      _memory,
      value.length,
      _memory + _capacity,
      pattern.length,
      mode,
      start,
    );
  }

  void close() {
    _library.close();
    DynamicLibrary.process().lookupFunction<
      Void Function(Pointer<Void>),
      void Function(Pointer<Void>)
    >('free')(_memory.cast());
  }
}
