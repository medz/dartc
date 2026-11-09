extension type Foreign<T>(int value) {
  bool _hidden(Object? input) => input is T;
  bool reveal(Object? input) => _hidden(input);
  bool Function(Object?) hide() => _hidden;
}
