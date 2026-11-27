// What a wrong index tells. Which argument it names differs between the
// official runtimes, so it is only told where it is given.
void assign(List<int> values, int index) {
  values[index] = 5;
}

void check(String what, void Function() test) {
  try {
    test();
  } on RangeError catch (error) {
    print((what, error.invalidValue, error.start, error.end));
  }
}

void main() {
  final values = <int>[1, 2, 3];
  check('growable', () => assign(values, 5)); // expect: (growable, 5, 0, 2)
  check('fixed', () => assign(List.filled(3, 0), -1)); // expect: (fixed, -1, 0, 2)
  check('read', () => values[3]); // expect: (read, 3, 0, 2)
  try {
    RangeError.checkValidIndex(5, values, 'index');
  } on RangeError catch (error) {
    print((error.name, error.invalidValue, error.start, error.end));
  }
  // expect: (index, 5, 0, 2)
}
