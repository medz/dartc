class C {
  T m<T>(T value) => value;
}

void show(C? receiver) {
  final int Function(int)? f = receiver?.m;
  print(f == null);
  print(f?.call(7));
  final g = receiver?.m;
  print(g == null);
  print(receiver?.m<int>(3));
  if (receiver != null) {
    final int Function(int) h = receiver.m;
    print(h(4));
  }
}

void main() {
  show(null);
  // expect: true
  // expect: null
  // expect: true
  // expect: null
  show(C());
  // expect: false
  // expect: 7
  // expect: false
  // expect: 3
  // expect: 4
}
