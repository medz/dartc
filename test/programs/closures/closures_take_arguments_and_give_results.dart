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

void main() {
  number(apply((n) => n + 1, 4)); // expect: 5
  number(
    apply((int n) {
      return n * n;
    }, 5),
  ); // expect: 25
  run(() => print('run')); // expect: run
  run(() {
    print('block');
  }); // expect: block
  final f = (int a, [int b = 2, int? c]) => a * 100 + b * 10 + (c ?? 0);
  number(f(1)); // expect: 120
  number(f(1, 5)); // expect: 150
  number(f(1, 5, 7)); // expect: 157
  final g = ({int a = 1, required int b}) => a - b;
  number(g(b: 4)); // expect: -3
  number(g(b: 4, a: 9)); // expect: 5
  final h = (double d, bool b) => b ? d : -d;
  truth(h(1.5, false) == -1.5); // expect: true
  number((() => 7)()); // expect: 7
  number(((int n) => n)(8)); // expect: 8
  Object? Function(Object?) k = (o) => o;
  show(k(3)); // expect: 3
  show(k(null)); // expect: null
  show(k(true)); // expect: true
  final w = () {};
  w();
  dynamic Function() z = () {};
  show(z()); // expect: null
  int Function(int) Function(int) add = (a) =>
      (b) => a + b;
  number(add(3)(4)); // expect: 7
  final A Function() m = () => A(6);
  number(m().n); // expect: 6
}

void number(int n) => print(n);

void truth(bool b) => print(b);
