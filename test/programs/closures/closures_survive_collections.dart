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

class L {
  L? next;
  int n = 0;
}

void main() {
  int Function()? f;
  for (var i = 0; i < 50; i++) {
    final l = L();
    l.n = i;
    final old = f;
    var c = 0;
    f = () {
      c += l.n;
      return c + (old == null ? 0 : old());
    };
  }
  show(f?.call()); // expect: 1225
  show(f?.call()); // expect: 2450
}

void number(int n) => print(n);

void truth(bool b) => print(b);
