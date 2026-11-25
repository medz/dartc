extension E on int {
  external int get x;
  external void f(int a);
}

void main() {
  for (final use in [() => 1.x, () => 1.f(2)]) {
    try {
      use();
    } catch (e) {
      print(e.runtimeType);
    }
  }
  // expect: NoSuchMethodError
  // expect: NoSuchMethodError
}
