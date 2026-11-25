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

int Function() counter(int from) {
  var n = from;
  return () => n++;
}

void main() {
  final a = 5;
  var b = 6;
  number((() => a + b)()); // expect: 11
  b = 7;
  number((() => a + b)()); // expect: 12
  final c = counter(10), d = counter(20);
  number(c()); // expect: 10
  number(c()); // expect: 11
  number(d()); // expect: 20
  number(c()); // expect: 12
  var sum = 0;
  void add(int n) {
    sum += n;
  }

  add(3);
  add(4);
  number(sum); // expect: 7
  final f = add;
  f(5);
  number(sum); // expect: 12
  run(() => sum = 100);
  number(sum); // expect: 100
  int x;
  x = 1;
  final g = () => x;
  x = 2;
  number(g()); // expect: 2
  double dd = 1.5;
  bool bb = true;
  A? aa;
  Object? oo = 4;
  final t = () {
    dd += 1;
    bb = !bb;
    aa = A(dd.toInt());
    oo = null;
  };
  t();
  truth(dd == 2.5); // expect: true
  truth(bb); // expect: false
  number(aa?.n ?? -1); // expect: 2
  show(oo); // expect: null
  num m = 1;
  run(() => m = 2.5);
  show(m);
  // expect: double
  // expect: 5
  int? z;
  run(() {
    z = (z ?? 0) + 1;
  });
  show(z); // expect: 1
}

void number(int n) => print(n);

void truth(bool b) => print(b);
