class C {
  T m<T>(T x) => x;

  void show() => print((this?.m<int>)!(1));
}

void main() {
  C().show(); // expect: 1
}
