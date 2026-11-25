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
  var n = 0;
  final f = (int k) {
    try {
      n += k;
      if (k > 2) throw A(k);
      return n;
    } on A catch (e) {
      run(() => n += e.n * 10);
      rethrow;
    } finally {
      run(() => n++);
    }
  };
  number(f(1)); // expect: 1
  try {
    f(3);
  } on A catch (e) {
    run(() => number(e.n));
  }
  // expect: 3
  number(n); // expect: 36
  try {
    run(() => throw B(5));
  } on B catch (e) {
    number(e.n);
  }
  // expect: 5
  for (var i = 0; i < 3; i++) {
    try {
      run(() {
        if (i == 1) throw A(i);
        number(i);
      });
    } catch (e) {
      print('caught');
      continue;
    } finally {
      run(() => n += i);
    }
  }
  // expect: 0
  // expect: caught
  // expect: 2
  number(n); // expect: 39
  var x = 1;
  try {
    x = 2;
    run(() {
      x = 3;
      throw C();
    });
  } on C {
    number(x);
  }
  // expect: 3
}

class C implements Exception {}

void number(int n) => print(n);

void truth(bool b) => print(b);
