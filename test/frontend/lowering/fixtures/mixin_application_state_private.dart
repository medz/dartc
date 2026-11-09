mixin PrivateMixin {
  int _value() => 41;
  int Function() privateClosure() =>
      () => _value();
  int Function() privateTearoff() => _value;
}
