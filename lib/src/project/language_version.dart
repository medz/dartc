import 'package:dartc/parser.dart';
import 'package:dartc/scanner.dart';
import 'package:dartc/source.dart';

(LanguageVersion?, SourceSpan)? versionOverride(ScanResult input) {
  final first = input.tokens.first.kind == .scriptTag
      ? input.tokens[1].start
      : input.tokens.first.start;
  for (final comment in input.comments) {
    if (comment.start >= first) break;
    final match = _marker.firstMatch(comment.lexeme);
    if (match == null) continue;
    final major = _component(match[1]!);
    final minor = _component(match[2]!);
    if (major == null || minor == null) {
      return (null, comment.span);
    }
    return (LanguageVersion(major, minor), comment.span);
  }
  return null;
}

int? _component(String digits) {
  if (digits.length < 16) return int.tryParse(digits);
  var start = 0;
  while (start < digits.length - 1 && digits.codeUnitAt(start) == 0x30) {
    start++;
  }
  if (digits.length - start > 19) return null;
  final value = BigInt.parse(digits.substring(start));
  return value.bitLength <= 63 && value.isValidInt ? value.toInt() : null;
}

final _marker = RegExp(r'^//[ \t]*@dart[ \t]*=[ \t]*([0-9]+)\.([0-9]+)[ \t]*$');
