import 'token_kind.dart';

final _keywords = _buildKeywords();

TokenKind keywordKind(String text, int start, int end) {
  final length = end - start;
  if (length < 2 || length > _keywords.maximumLength) return .identifier;
  final entries = _keywords.entries;
  var index = _hash(text, start, end, _keywords.shift);
  var kind = entries[index];
  while (kind != null) {
    final spelling = kind.spelling!;
    if (spelling.length == length && text.startsWith(spelling, start)) {
      return kind;
    }
    index = (index + 1) & (entries.length - 1);
    kind = entries[index];
  }
  return .identifier;
}

({List<TokenKind?> entries, int shift, int maximumLength}) _buildKeywords() {
  final words = [
    for (final kind in TokenKind.values)
      if (kind.isKeyword) kind,
  ];
  var size = 1;
  var shift = 32;
  while (size < words.length * 2) {
    size *= 2;
    shift--;
  }
  final entries = List<TokenKind?>.filled(size, null);
  var maximumLength = 0;
  for (final kind in words) {
    final spelling = kind.spelling!;
    if (spelling.length > maximumLength) maximumLength = spelling.length;
    var index = _hash(spelling, 0, spelling.length, shift);
    while (entries[index] != null) {
      index = (index + 1) & (size - 1);
    }
    entries[index] = kind;
  }
  return (entries: entries, shift: shift, maximumLength: maximumLength);
}

int _hash(String text, int start, int end, int shift) {
  final key =
      text.codeUnitAt(start) |
      text.codeUnitAt(start + 1) << 8 |
      text.codeUnitAt(end - 1) << 16 |
      (end - start) << 24;
  return ((key * 0x9E3779B9) & 0xFFFFFFFF) >>> shift;
}
