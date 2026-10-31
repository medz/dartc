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
    final major = int.tryParse(match[1]!);
    final minor = int.tryParse(match[2]!);
    if (major == null || minor == null) {
      return (null, comment.span);
    }
    return (LanguageVersion(major, minor), comment.span);
  }
  return null;
}

final _marker = RegExp(r'^//[ \t]*@dart[ \t]*=[ \t]*([0-9]+)\.([0-9]+)[ \t]*$');
