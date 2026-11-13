import 'unicode_case_data.dart' as data;

/// Applies the language-independent Unicode full case mapping.
String convertCase(String text, {required bool upper}) {
  final mapping = upper ? data.upper : data.lower;
  StringBuffer? result;
  var offset = 0;
  var precededByCased = false;
  for (final code in text.runes) {
    var replacement = mapping[code];
    if (!upper &&
        code == 0x03a3 &&
        precededByCased &&
        !_followedByCased(text, offset + 1)) {
      replacement = '\u03c2';
    }
    if (replacement != null) {
      result ??= StringBuffer(text.substring(0, offset));
      result.write(replacement);
    } else {
      result?.writeCharCode(code);
    }
    // Case-ignorable takes precedence even when a character is also cased.
    if (!upper && !data.ignored.contains(code)) {
      precededByCased = data.cased.contains(code);
    }
    offset += code > 0xffff ? 2 : 1;
  }
  return result?.toString() ?? text;
}

bool _followedByCased(String text, int offset) {
  final iterator = RuneIterator.at(text, offset);
  while (iterator.moveNext()) {
    final code = iterator.current;
    if (!data.ignored.contains(code)) return data.cased.contains(code);
  }
  return false;
}
