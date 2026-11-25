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
  int fact(int n) => n < 2 ? 1 : n * fact(n - 1);
  number(fact(5)); // expect: 120
  bool isEven(int n) {
    bool odd(int m) => m == 0 ? false : isEven(m - 1);
    return n == 0 ? true : odd(n - 1);
  }

  truth(isEven(10)); // expect: true
  truth(isEven(7)); // expect: false
  int total = 0;
  void walk(int n) {
    if (n == 0) return;
    total += n;
    final next = walk;
    next(n - 1);
  }

  walk(4);
  number(total); // expect: 10
  truth(fact == fact); // expect: true
  int f({int a = 1}) => a;
  number(f()); // expect: 1
  number(f(a: 3)); // expect: 3
}

void number(int n) => print(n);

void truth(bool b) => print(b);
