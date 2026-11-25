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
  final int n;
  P(this.n, [int k = 1]) {
    number(n + k);
  }
  P.twice(int n) : this(n * 2);
  factory P.made(int n) => P(n + 1000);
  P.none() : n = 0;
}

P build(P Function(int) f, int n) => f(n);
void main() {
  number(build(P.new, 3).n);
  // expect: 4
  // expect: 3
  number(build(P.twice, 4).n);
  // expect: 9
  // expect: 8
  number(build(P.made, 5).n);
  // expect: 1006
  // expect: 1005
  final f = P.none;
  number(f().n); // expect: 0
  final g = P.new;
  number(g(6, 7).n);
  // expect: 13
  // expect: 6
  truth(P.new == P.new); // expect: true
  truth(P.twice == P.new); // expect: false
  A Function(int) a = B.new;
  number(a(9).add(1)); // expect: 110
}

void number(int n) => print(n);

void truth(bool b) => print(b);
