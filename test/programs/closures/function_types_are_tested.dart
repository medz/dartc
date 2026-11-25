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

int opt(int a, [int b = 1]) => a;
void named({int x = 1}) {}
A back(Object o) => A(1);
Object? pick(int n) {
  switch (n) {
    case 0:
      return twice;
    case 1:
      return opt;
    case 2:
      return named;
    case 3:
      return back;
    case 4:
      return () => 1;
    case 5:
      return A(1).shout;
    case 6:
      return 5;
    case 7:
      return null;
    case 8:
      return B(2).add;
    case 9:
      return A.new;
  }
  return A(2).add;
}

void main() {
  for (var i = 0; i < 11; i++) {
    final o = pick(i);
    truth(o is Function);
    truth(o is int Function(int));
    truth(o is void Function());
    truth(o is num Function(int));
    truth(o is A Function(A));
    truth(o is void Function({int x}));
    truth(o is int Function(int, int));
    truth(o is int Function(int)?);
    truth(o is Object);
    truth(o is A);
    truth(o is! Function);
    truth(o is dynamic Function(Never));
    truth(o is Object? Function());
  }
  // expect: true
  // expect: true
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: true
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: true
  // expect: true
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: true
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: true
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: true
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: true
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: true
  // expect: true
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: true
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: true
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: true
  // expect: true
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: true
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  Object o = twice;
  if (o is int Function(int)) number(o(4)); // expect: 8
  number((o as int Function(int))(5)); // expect: 10
  try {
    o as void Function();
  } on TypeError {
    print('a');
  }
  // expect: a
  try {
    Object? n;
    n as Function;
  } on TypeError {
    print('b');
  }
  // expect: b
  Object f = () => 3;
  final g = f as Function;
  truth(g == f); // expect: true
}

void number(int n) => print(n);

void truth(bool b) => print(b);
