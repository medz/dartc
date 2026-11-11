bool compare(Object? a, Object? b) => identical(a, b);

bool compareValue(Object? a, Object? b) {
  final compare = identical;
  return compare(a, b);
}

bool shadowed(Object? value) {
  bool identical(Object? a, Object? b) => false;
  return identical(value, value);
}
