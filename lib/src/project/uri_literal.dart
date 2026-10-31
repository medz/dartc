import 'package:dartc/ast.dart';

String uriLiteral(StringExpression expression) {
  final output = StringBuffer();
  final pending = <StringExpression>[expression];
  while (pending.isNotEmpty) {
    switch (pending.removeLast()) {
      case StringLiteralExpression(:final text):
        output.write(_literal(text));
      case AdjacentStringsExpression(:final strings):
        pending.addAll(strings.reversed);
      default:
        throw const FormatException(
          'A URI requires a non-interpolated string.',
        );
    }
  }
  return output.toString();
}

String _literal(String text) {
  final raw = text.startsWith('r');
  var start = raw ? 1 : 0;
  if (text.length < start + 2) {
    throw const FormatException('Unfinished string.');
  }
  final quote = text[start];
  final triple = text.startsWith(quote * 3, start);
  final width = triple ? 3 : 1;
  start += width;
  final end = text.length - width;
  if (start > end || !text.endsWith(quote * width)) {
    throw const FormatException('Unfinished string.');
  }
  if (triple) {
    var line = start;
    while (line < end &&
        (text.codeUnitAt(line) == 32 || text.codeUnitAt(line) == 9)) {
      line++;
    }
    if (line < end && text.codeUnitAt(line) == 13) {
      start = line + 1;
      if (start < end && text.codeUnitAt(start) == 10) start++;
    } else if (line < end && text.codeUnitAt(line) == 10) {
      start = line + 1;
    }
  }
  final output = StringBuffer();
  for (var index = start; index < end; index++) {
    var code = text.codeUnitAt(index);
    if (code == 13) {
      if (index + 1 < end && text.codeUnitAt(index + 1) == 10) index++;
      output.writeCharCode(10);
      continue;
    }
    if (raw || code != 92) {
      output.writeCharCode(code);
      continue;
    }
    if (++index >= end) throw const FormatException('Unfinished escape.');
    code = text.codeUnitAt(index);
    if (code == 120 || code == 117) {
      final braced = code == 117 && index + 1 < end && text[index + 1] == '{';
      final first = index + (braced ? 2 : 1);
      final last = braced
          ? text.indexOf('}', first)
          : first + (code == 120 ? 2 : 4);
      if (last <= first || last > end || braced && last - first > 6) {
        throw const FormatException('Invalid hexadecimal escape.');
      }
      final value = int.tryParse(text.substring(first, last), radix: 16);
      if (value == null || value < 0 || value > 0x10ffff) {
        throw const FormatException('Invalid Unicode escape.');
      }
      output.writeCharCode(value);
      index = braced ? last : last - 1;
    } else {
      output.writeCharCode(switch (code) {
        110 => 10,
        114 => 13,
        102 => 12,
        98 => 8,
        116 => 9,
        118 => 11,
        _ => code,
      });
    }
  }
  return output.toString();
}
