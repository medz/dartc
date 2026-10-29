import 'diagnostic.dart';

// Native names must have an exact UTF-8 representation; do not replace surrogates.
List<int> encodeUtf8(String value) {
  final bytes = <int>[];
  var i = 0;
  while (i < value.length) {
    var code = value.codeUnitAt(i++);
    if (code >= 0xd800 && code <= 0xdbff && i < value.length) {
      final low = value.codeUnitAt(i);
      if (low >= 0xdc00 && low <= 0xdfff) {
        code = 0x10000 + ((code - 0xd800) << 10) + low - 0xdc00;
        i++;
      }
    }
    if (code >= 0xd800 && code <= 0xdfff)
      throw Diagnostic(
        'dartc: UTF-8 output contains an unpaired UTF-16 surrogate',
      );
    if (code < 0x80) {
      bytes.add(code);
    } else {
      if (code < 0x800) {
        bytes.add(0xc0 | (code >> 6));
      } else if (code < 0x10000) {
        bytes.add(0xe0 | (code >> 12));
        bytes.add(0x80 | ((code >> 6) & 63));
      } else {
        bytes.add(0xf0 | (code >> 18));
        bytes.add(0x80 | ((code >> 12) & 63));
        bytes.add(0x80 | ((code >> 6) & 63));
      }
      bytes.add(0x80 | (code & 63));
    }
  }
  return bytes;
}
