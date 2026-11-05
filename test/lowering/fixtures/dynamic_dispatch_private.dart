class PrivateBox() {
  // Accessed dynamically.
  // ignore: unused_element
  int _value() => 41;
  @override
  dynamic noSuchMethod(Invocation invocation) => 7;
}

int callPrivate(dynamic value) => value._value();
