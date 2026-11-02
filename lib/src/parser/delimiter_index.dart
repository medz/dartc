import 'dart:typed_data';

import 'package:dartc/scanner.dart';

// Opening tokens point past their closer. A zero link means no complete pair.
final class DelimiterIndex {
  DelimiterIndex(List<Token> tokens)
    : _links = tokens.length < 1 << 30
          ? Uint32List(tokens.length)
          : Uint64List(tokens.length) {
    final parentheses = <int>[], brackets = <int>[], braces = <int>[];
    // The high bits count consumed '>' characters in a compound token.
    final shift = tokens.length < 1 << 30 ? 30 : 60;
    final mask = (1 << shift) - 1;
    var next = 0;
    var available = 0, last = -1;
    for (var i = tokens.length - 1; i >= 0; i--) {
      switch (tokens[i].kind) {
        case .greater ||
            .greaterEqual ||
            .shiftRight ||
            .shiftRightAssign ||
            .unsignedShiftRight ||
            .unsignedShiftRightAssign:
          _links[i] = next;
          next = i + 1;
        case .less when next != 0:
          final end = next & mask;
          final token = tokens[end - 1];
          final used = (next >> shift) + 1;
          if (used == token.length) _links[i] = end;
          final count = switch (token.kind) {
            .greater || .greaterEqual => 1,
            .shiftRight || .shiftRightAssign => 2,
            _ => 3,
          };
          next = used == count ? _links[end - 1] : end | (used << shift);
        case .rightParen || .rightBracket || .rightBrace:
          final stack = switch (tokens[i].kind) {
            .rightParen => parentheses,
            .rightBracket => brackets,
            _ => braces,
          };
          stack.add(i);
          stack.add(available);
          _links[i] = next;
          next = available = 0;
        case .leftParen || .leftBracket || .leftBrace:
          final stack = switch (tokens[i].kind) {
            .leftParen => parentheses,
            .leftBracket => brackets,
            _ => braces,
          };
          if (stack.isEmpty) {
            next = available = 0;
          } else {
            available = stack.removeLast();
            final close = stack.removeLast();
            _links[i] = close + 1;
            next = _links[close];
          }
        case .colon:
          if (last < 0) last = i;
          _links[i] = available;
          available = i + 1;
        case .question:
          _links[i] = available;
          // An ordinary conditional consumes a colon before an outer trial can use it.
          if (available != 0 && i > 0 && _plainQuestion(tokens, i)) {
            available = _links[available - 1];
          }
        case .semicolon:
          next = available = 0;
        default:
          break;
      }
    }
    lastColon = last;
  }

  late final int lastColon;
  final List<int> _links;

  bool allowsConditional(int question) => _links[question] != 0;

  int? afterTypeArguments(int opening) {
    final end = _links[opening];
    return end == 0 ? null : end;
  }

  int? closing(int opening) {
    final end = _links[opening];
    return end == 0 ? null : end - 1;
  }
}

bool _plainQuestion(List<Token> tokens, int i) {
  final left = tokens[i - 1].kind;
  final right = tokens[i + 1].kind;
  if (left == .rightBracket && right != .leftBracket) return true;
  if (left != .identifier) return false;
  if (right == .integer ||
      right == .doubleLiteral ||
      right == .hexadecimalInteger ||
      right == .keywordTrue ||
      right == .keywordFalse ||
      right == .keywordNull) {
    return true;
  }
  if (right != .identifier) return false;
  return switch (tokens[i + 2].kind) {
    .assign ||
    .semicolon ||
    .comma ||
    .keywordIn ||
    .rightParen ||
    .rightBrace ||
    .rightBracket ||
    .eof => false,
    _ => true,
  };
}
