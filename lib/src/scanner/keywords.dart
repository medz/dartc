import 'token_kind.dart';

final _keywords = {
  for (final kind in TokenKind.values)
    if (kind.isKeyword) kind.spelling!: kind,
};

TokenKind keywordKind(String text) => _keywords[text] ?? .identifier;
