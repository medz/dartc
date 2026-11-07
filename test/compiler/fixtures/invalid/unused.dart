int valid() => 1;

int unused() {
  // ignore: invalid_assignment
  int value = 'invalid';
  return value;
}
