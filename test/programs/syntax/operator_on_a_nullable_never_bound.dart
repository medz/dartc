extension NullableAdd on Never? {
  int operator +(int right) => right + 1;
}

int add<T extends Never>(T? value) => value + 2;

void main() {
  print(add<Never>(null)); // expect: 3
}
