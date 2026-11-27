// Covariant checks and casts against type parameters whose arguments are
// int, String, double or bool, and others.
class Box<T> {
  T? value;
  void put(Object? value) => this.value = value as T;
  bool holds(Object? value) => value is T;
}

class Numbers<T extends num> {
  bool holds(Object? value) => value is T;
}

void check(void Function() put) {
  try {
    put();
    print('fits');
  } on TypeError {
    print('does not fit');
  }
}

void main() {
  final ints = <int>[1, 2];
  final List<Object?> objects = ints;
  check(() => objects[0] = 3); // expect: fits
  check(() => objects[0] = 1 << 62); // expect: fits
  check(() => objects[0] = 'a'); // expect: does not fit
  check(() => objects[0] = null); // expect: does not fit
  check(() => objects[0] = 1.5); // expect: does not fit
  final List<Object?> texts = <String>['a'];
  check(() => texts[0] = 'b'); // expect: fits
  check(() => texts[0] = 1); // expect: does not fit
  final List<Object?> floats = <double>[1.5];
  check(() => floats[0] = 2.5); // expect: fits
  check(() => floats[0] = 2); // expect: does not fit
  final List<Object?> flags = <bool>[true];
  check(() => flags[0] = false); // expect: fits
  check(() => flags[0] = 'true'); // expect: does not fit
  final List<Object?> numbers = <num>[1];
  check(() => numbers[0] = 1.5); // expect: fits
  check(() => numbers[0] = 'x'); // expect: does not fit
  final List<Object?> maybe = <int?>[1];
  check(() => maybe[0] = null); // expect: fits
  check(() => maybe[0] = 'x'); // expect: does not fit
  print(Box<int>().holds(1)); // expect: true
  print(Box<int>().holds(null)); // expect: false
  print(Box<String>().holds('a')); // expect: true
  print(Box<String>().holds(1)); // expect: false
  print(Box<Object>().holds(1)); // expect: true
  print(Box<Comparable<int>>().holds(1)); // expect: false
  print(Numbers<int>().holds(1)); // expect: true
  print(Numbers<double>().holds(1)); // expect: false
  print(Numbers<num>().holds(1.5)); // expect: true
  check(() => Box<double>().put(1.5)); // expect: fits
  check(() => Box<bool>().put(1)); // expect: does not fit
}
