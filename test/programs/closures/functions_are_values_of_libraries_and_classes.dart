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

class S {
  static int half(int n) => n ~/ 2;
  static int Function(int) f = twice;
  int Function(int) g = half;
}

int Function(int) pick(bool b) => b ? twice : S.half;
void main() {
  number(apply(twice, 4)); // expect: 8
  number(apply(S.half, 9)); // expect: 4
  number(pick(true)(5)); // expect: 10
  number(pick(false)(8)); // expect: 4
  var f = twice;
  number(f(3)); // expect: 6
  f = S.half;
  number(f(3)); // expect: 1
  number(f.call(7)); // expect: 3
  final g = f.call;
  number(g(20)); // expect: 10
  number(S.f(6)); // expect: 12
  S.f = S.half;
  number(S.f(6)); // expect: 3
  number(S().g(10)); // expect: 5
  final s = S();
  s.g = twice;
  number(s.g(10)); // expect: 20
  number((s.g)(11)); // expect: 22
  truth(twice == twice); // expect: true
  truth(identical(twice, twice)); // expect: true
  truth(twice == S.half); // expect: false
  Object o = twice;
  truth(o == twice); // expect: true
  truth(o == f); // expect: false
  int Function(int)? n;
  truth(n == null); // expect: true
  n = twice;
  number(n(1)); // expect: 2
  n = null;
  show(n?.call(3)); // expect: null
  show((n ?? S.half)(100)); // expect: 50
}

void number(int n) => print(n);

void truth(bool b) => print(b);
