class C {
  C Function() f() =>
      () => this;
  T m<T>(T x) => x;

  void show() {
    print((this?.m<int>)!(1));
    print((this?.f()().m<int>)!(2));
  }
}

void main() {
  C().show();
  // expect: 1
  // expect: 2
}
