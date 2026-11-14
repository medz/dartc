class const Token(final int value);

bool constantAndFresh() => identical(const Token(1), Token(1));

bool freshAndConstant() => identical(Token(1), const Token(1));

bool sameConstant() => identical(const Token(1), const Token(1));

bool differentConstants() => identical(const Token(1), const Token(2));

bool selectedIdentity(bool selected) =>
    identical(const Token(1), selected ? const Token(1) : Token(1));

bool unknownIdentity(Object value) => identical(const Token(1), value);
