extension D<T> on int {
  Type get type => T;
  set type(Type other) => print((T, other));
  int get count => 1;
  set count(int other) => print((T, other));
  int operator [](int at) => at;
  void operator []=(int at, int value) => print((T, at, value));
  Type operator +(String a) => T;
  Type operator -() => T;
  Type call() => T;
  Type m() => T;
}

class K {}

extension E<T> on K {
  K operator +(int other) {
    print(T);
    return this;
  }
}

extension F<T> on int {
  K get k => K();
  set k(K other) => print(T);
}

void main() {
  D<String>(1).type = int; // expect: (String, int)
  D<String>(1).count++; // expect: (String, 2)
  ++D<bool>(1).count; // expect: (bool, 2)
  D<String>(1).count += 3; // expect: (String, 4)
  D<String>(1)[2] = 3; // expect: (String, 2, 3)
  D<String>(1)[2]++; // expect: (String, 2, 3)
  D<String>(1)[2] -= 1; // expect: (String, 2, 1)
  print(-D<String>(1)); // expect: String
  print(D<String>(1)()); // expect: String
  print(D<String>(1).m()); // expect: String
  final m = D<String>(1).m;
  print(m()); // expect: String
  F<String>(1).k++;
  // expect: dynamic
  // expect: String
  F<String>(1).k += 2;
  // expect: dynamic
  // expect: String
  F<String>(1).k + 3; // expect: dynamic
}
