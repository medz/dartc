import 'dart:ffi';

import 'package:dartc/interop.dart';

int? parse(String source, int? radix, int mode) => switch (mode) {
  0 => int.parse(source, radix: radix),
  1 => int.tryParse(source, radix: radix),
  2 => int.parse.call(source, radix: radix),
  _ => int.tryParse.call(source, radix: radix),
};

String format(int value, int radix, int mode) => switch (mode) {
  0 => value.toRadixString(radix),
  1 => value.toRadixString.call(radix),
  2 => value.toString(),
  3 => (value as Object).toString(),
  4 => (value as num).toString(),
  _ => value.toString.call(),
};

@Export<Int32 Function(Pointer<Uint16>, IntPtr, Int32, Int32, Pointer<Int64>)>()
int parseBuffer(
  Pointer<Uint16> input,
  int length,
  int radix,
  int mode,
  Pointer<Int64> output,
) {
  final source = String.fromCharCodes(input.asTypedList(length));
  try {
    final value = parse(source, radix == 0 ? null : radix, mode);
    if (value == null) return 1;
    output.value = value;
    return 0;
  } on FormatException catch (error) {
    return identical(error.source, source) ? 2 : 9;
  } on RangeError {
    return 3;
  }
}

@Export<Int32 Function(Int64, Int32, Int32, Pointer<Uint16>, IntPtr)>()
int formatBuffer(
  int value,
  int radix,
  int mode,
  Pointer<Uint16> output,
  int capacity,
) {
  try {
    final text = format(value, radix, mode);
    if (text.length > capacity) return -2;
    for (var i = 0; i < text.length; i++) {
      output[i] = text.codeUnitAt(i);
    }
    return text.length;
  } on RangeError {
    return -1;
  }
}
