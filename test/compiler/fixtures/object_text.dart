import 'dart:ffi';

import 'package:dartc/interop.dart';

import 'core_collections.dart';

String formatDouble(double value, int mode, int digits) => switch (mode) {
  0 => value.toString(),
  1 => value.toStringAsFixed(digits),
  2 => value.toStringAsExponential(digits < 0 ? null : digits),
  _ => value.toStringAsPrecision(digits),
};

@Export<Int32 Function(Double, Int32, Int32, Pointer<Uint16>, IntPtr)>()
int formatBuffer(
  double value,
  int mode,
  int digits,
  Pointer<Uint16> output,
  int capacity,
) {
  try {
    final text = formatDouble(value, mode, digits);
    if (text.length > capacity) return -2;
    output.asTypedList(text.length).setAll(0, text.codeUnits);
    return text.length;
  } on RangeError {
    return -1;
  } catch (error) {
    final text = 'Unexpected error: $error';
    output.asTypedList(text.length).setAll(0, text.codeUnits);
    return text.length;
  }
}

@Export<Int32 Function(Int32, Pointer<Uint16>, IntPtr)>()
int collectionBuffer(int mode, Pointer<Uint16> output, int capacity) {
  final text = collectionText(mode);
  if (text.length > capacity) return -2;
  output.asTypedList(text.length).setAll(0, text.codeUnits);
  return text.length;
}
