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

int Function(int) outer(int a, {int b = 2}) {
  a += 1;
  return (c) {
    b++;
    int inner(int d) {
      a += d;
      return a * 1000 + b * 100 + c * 10 + d;
    }

    return inner(c);
  };
}

void deep(int n) {
  void go(int k) {
    if (k > 0) {
      final here = k;
      run(
        () => run(
          () => run(() {
            n += here;
            go(k - 1);
          }),
        ),
      );
    }
  }

  go(n);
  number(n);
}

void main() {
  final f = outer(3);
  number(f(4)); // expect: 8344
  number(f(5)); // expect: 13455
  number(outer(1, b: 7)(2)); // expect: 4822
  deep(4); // expect: 14
}

void number(int n) => print(n);

void truth(bool b) => print(b);
