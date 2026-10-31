import 'dart:typed_data';

import 'package:dartc/scanner.dart';

// Parser lookahead only: pairing does not diagnose mismatched delimiters.
// Different delimiter kinds stay independent so recovery can find a closer
// beyond an unmatched delimiter of another kind.
final class DelimiterIndex(final List<Token> _tokens) {
  // Skips a possible type argument/parameter list without parsing annotations.
  // The type reader still validates the candidate. Parentheses, brackets and
  // braces hide expression operators from the angle count.
  int? afterTypeArguments(int start) {
    if (_typeEnds.containsKey(start)) return _typeEnds[start];
    final pending = [start];
    for (var index = start + 1; index < _tokens.length; index++) {
      final kind = _tokens[index].kind;
      if (kind == .leftParen || kind == .leftBracket || kind == .leftBrace) {
        final end = closing(index);
        if (end == null) break;
        index = end;
      } else if (kind == .less) {
        pending.add(index);
      } else {
        final count = switch (kind) {
          .greater || .greaterEqual => 1,
          .shiftRight || .shiftRightAssign => 2,
          .unsignedShiftRight || .unsignedShiftRightAssign => 3,
          _ => 0,
        };
        for (var consumed = 1; consumed <= count; consumed++) {
          final opening = pending.removeLast();
          final end = consumed == _tokens[index].length ? index + 1 : null;
          _typeEnds[opening] = end;
          if (pending.isEmpty) return end;
        }
        if (kind == .semicolon ||
            kind == .rightParen ||
            kind == .rightBracket ||
            kind == .rightBrace ||
            kind == .eof) {
          break;
        }
      }
    }
    for (final opening in pending) {
      _typeEnds[opening] = null;
    }
    return null;
  }

  late final Map<int, int?> _typeEnds = {};

  // Returns the matching token index, or null for an unclosed delimiter.
  int? closing(int start) {
    final opening = _tokens[start].kind;
    final closing = switch (opening) {
      TokenKind.leftParen => TokenKind.rightParen,
      TokenKind.leftBracket => TokenKind.rightBracket,
      TokenKind.leftBrace => TokenKind.rightBrace,
      _ => throw ArgumentError.value(
        start,
        'start',
        'Expected an opening delimiter.',
      ),
    };
    if (_tokens[start + 1].kind == closing) return start + 1;
    if (_tokens[start + 1].kind != opening &&
        start + 2 < _tokens.length &&
        _tokens[start + 2].kind == closing) {
      return start + 2;
    }
    final known = _ends[start];
    if (known != 0) return known == -1 ? null : known - 1;
    final pending = [start];
    for (var index = start + 1; index < _tokens.length; index++) {
      final kind = _tokens[index].kind;
      if (kind == opening) {
        pending.add(index);
      } else if (kind == closing) {
        _ends[pending.removeLast()] = index + 1;
        if (pending.isEmpty) return index;
      }
    }
    for (final index in pending) {
      _ends[index] = -1;
    }
    return null;
  }

  // Zero is unknown, -1 is unclosed, and a positive value is the end plus one.
  late final Int64List _ends = Int64List(_tokens.length);
}
