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

int opt(int a, [int b = 10, int c = 100]) => a + b + c;
int named(int a, {int b = 10, required int c}) => a * 1000 + b * 100 + c;
double mix(double d, bool b, Object? o, num n, int? i) {
  show(o);
  show(n);
  show(i);
  return b ? d : -d;
}

void nothing() {
  print('nothing');
}

dynamic any() => 5;
A make(A a) => a;
Never fail(int n) => throw A(n);
void main() {
  int Function(int) f = opt;
  number(f(1)); // expect: 111
  int Function(int, int) g = opt;
  number(g(1, 2)); // expect: 103
  var h = opt;
  number(h(1)); // expect: 111
  number(h(1, 2)); // expect: 103
  number(h(1, 2, 3)); // expect: 6
  int Function(int, {required int c}) k = named;
  number(k(1, c: 5)); // expect: 2005
  var m = named;
  number(m(1, c: 5)); // expect: 2005
  number(m(1, c: 5, b: 6)); // expect: 1605
  number(m(c: trace(7), b: trace(8), trace(9)));
  // expect: 7
  // expect: 8
  // expect: 9
  // expect: 9807
  final x = mix;
  truth(x(1.5, false, 3, 4, null) < 0);
  // expect: 3
  // expect: 4
  // expect: null
  // expect: true
  truth(x(2, true, null, 1.5, 7) == 2);
  // expect: null
  // expect: double
  // expect: 3
  // expect: 7
  // expect: true
  run(nothing); // expect: nothing
  var v = nothing;
  v(); // expect: nothing
  var d = any;
  show(d()); // expect: 5
  Object? Function() e = any;
  show(e()); // expect: 5
  void Function() w = any;
  w();
  A Function(B) c = make;
  number(c(B(4)).n); // expect: 4
  num Function(int) z = twice;
  show(z(8)); // expect: 16
  Object Function(int) y = twice;
  show(y(9)); // expect: 18
  int Function(int) q = fail;
  try {
    q(3);
  } on A catch (e) {
    number(e.n);
  }
  // expect: 3
}

void number(int n) => print(n);

void truth(bool b) => print(b);

int trace(int n) {
  print(n);
  return n;
}
