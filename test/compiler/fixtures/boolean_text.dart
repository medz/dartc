import 'dart:ffi';

import 'package:dartc/interop.dart';

bool? parse(String source, bool caseSensitive, int mode) => switch (mode) {
  0 => bool.parse(source, caseSensitive: caseSensitive),
  1 => bool.tryParse(source, caseSensitive: caseSensitive),
  2 => bool.parse.call(source, caseSensitive: caseSensitive),
  3 => bool.tryParse.call(source, caseSensitive: caseSensitive),
  4 => bool.parse(source),
  _ => bool.tryParse(source),
};

@Export<Int8 Function(Pointer<Uint16>, IntPtr, Bool, Int32, Pointer<Bool>)>()
int parseBuffer(
  Pointer<Uint16> input,
  int length,
  bool caseSensitive,
  int mode,
  Pointer<Bool> output,
) {
  final source = String.fromCharCodes(input.asTypedList(length));
  try {
    final value = parse(source, caseSensitive, mode);
    if (value == null) return 1;
    output.value = value;
    return 0;
  } on FormatException catch (error) {
    return identical(error.source, source) ? 2 : 9;
  }
}
