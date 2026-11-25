class A<T> {
  void m<S extends T>() => print(S);
  void Function(T) f() =>
      (T x) => print(x);
  void g(T x) => print((T, x));
  void h(void Function(T) k) {}
}

class Trace {
  String log = '';
  int v = 1;
  int first() {
    log += 'A';
    return v;
  }

  S second() {
    log += 'B';
    return S(this);
  }
}

class S {
  final Trace t;
  S(this.t);
  String toString() {
    t.log += 'S';
    return '7';
  }
}

void main() {
  A<num> a = A<int>();
  try {
    final t = a.m;
    t<double>();
  } catch (e) {
    print(e);
  }
  // expect: type '<Y0 extends int>() => void' is not a subtype of type '<Y0 extends num>() => void'
  try {
    final t = a.f;
    t();
  } catch (e) {
    print(e);
  }
  // expect: type '() => (int) => void' is not a subtype of type '() => (num) => void'
  try {
    final t = a.g;
    t(1);
    t(1.5);
  } catch (e) {
    print(e);
  }
  // expect: (int, 1)
  // expect: type 'double' is not a subtype of type 'int' of 'x'
  try {
    final t = a.h;
    t((num x) {});
  } catch (e) {
    print(e);
  }
  try {
    final t = a.g;
    print(t.runtimeType);
  } catch (e) {
    print(e);
  }
  // expect: (Object?) => void
}
