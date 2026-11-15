class const Token(final int value);

bool constantAndFresh() => identical(const Token(1), Token(1));

bool freshAndConstant() => identical(Token(1), const Token(1));

bool sameConstant() => identical(const Token(1), const Token(1));

bool differentConstants() => identical(const Token(1), const Token(2));

bool selectedIdentity(bool selected) =>
    identical(const Token(1), selected ? const Token(1) : Token(1));

bool unknownIdentity(Object value) => identical(const Token(1), value);

bool sameInput(Object? value) => identical(value, value);

bool sameViews(Token? value) {
  final Object? left = value;
  final Object? right = value;
  return identical(left, right);
}

bool unknownPair(Object? left, Object? right) => identical(left, right);

Token makeToken() => Token(1);

bool freshAndFresh() => identical(Token(1), Token(1));

bool factoryFresh() => identical(makeToken(), makeToken());

bool compareFresh(Token first) => identical(first, makeToken());

bool nestedFactory() => compareFresh(makeToken());

bool selectedFresh(bool alias) {
  final first = makeToken();
  return identical(first, alias ? first : makeToken());
}

bool repeatedFresh(int count, bool alias) {
  var previous = makeToken();
  var result = false;
  for (var i = 0; i < count; i++) {
    final current = makeToken();
    result = identical(current, alias ? current : previous);
    previous = current;
  }
  return result;
}

Token returnToken(Token token) => token;

bool borrowedIdentity() {
  final token = makeToken();
  return identical(token, returnToken(token));
}

Token? published;

Token publishToken() {
  final token = makeToken();
  published = token;
  return token;
}

bool publishedIdentity() => identical(publishToken(), published);
