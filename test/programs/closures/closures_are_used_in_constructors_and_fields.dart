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

class P {
  final int Function() a;
  int Function(int)? b;
  P(int n) : a = (() => n * 2) {
    var m = n;
    b = (k) => m += k;
  }
  P.init(int n, {int Function(int)? this.b})
    : a = (() {
        n++;
        return n;
      });
}

int Function() g = () {
  var n = 0;
  return () => ++n;
}();
final k = (() => 5)();

class S {
  static int Function(int) s = (n) => n * k;
}

void main() {
  final p = P(4);
  number(p.a()); // expect: 8
  number(p.b!(3)); // expect: 7
  number(p.b!(3)); // expect: 10
  final q = P.init(6, b: (x) => -x);
  number(q.a()); // expect: 7
  number(q.a()); // expect: 8
  show(q.b?.call(9)); // expect: -9
  number(g()); // expect: 1
  number(g()); // expect: 2
  number(S.s(3)); // expect: 15
}

void number(int n) => print(n);

void truth(bool b) => print(b);
