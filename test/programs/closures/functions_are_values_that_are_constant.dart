void show(Object? o) {
  if (o == null) {
    print('null');
  } else if (o is int) {
    number(o);
  } else if (o is bool) {
    truth(o);
  } else if (o is double) {
    print('double');
    number((o * 2).toInt());
  } else {
    print('other');
  }
}

int twice(int n) => n * 2;
int apply(int Function(int) f, int n) => f(n);
void run(void Function() f) => f();

class A {
  final int n;
  const A(this.n);
  int add(int m) => n + m;
  void shout() => number(n);
  int get g => n;
}

class B extends A {
  const B(super.n);
  @override
  int add(int m, [int k = 100]) => n + m + k;
}

class K {
  final int Function(int) f;
  final Object o;
  const K(this.f, [this.o = twice]);
}

const int Function(int) c = twice;
const k = K(twice);
int def(int n, [int Function(int) f = twice]) => f(n);
int Function(int) g = c;

class S {
  static int t(int n) => n * 3;
  static const K s = K(t, S.t);
}

void main() {
  number(c(4)); // expect: 8
  number(k.f(5)); // expect: 10
  truth(identical(k, const K(twice))); // expect: true
  number(def(6)); // expect: 12
  number(def(6, S.t)); // expect: 18
  number(g(7)); // expect: 14
  number(S.s.f(8)); // expect: 24
  truth(k.o == twice); // expect: true
  truth(S.s.o == S.t); // expect: true
  truth(identical(c, twice)); // expect: true
}

void number(int n) => print(n);

void truth(bool b) => print(b);
