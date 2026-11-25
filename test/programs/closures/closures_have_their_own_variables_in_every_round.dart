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
  int Function()? a, b, c;
  for (var i = 0; i < 3; i++) {
    if (i == 0) a = () => i;
    if (i == 1) b = () => i;
    if (i == 2) c = () => i++;
  }
  show(a?.call()); // expect: 0
  show(b?.call()); // expect: 1
  show(c?.call()); // expect: 2
  show(c?.call()); // expect: 3
  for (var i = 0, j = 10; i < j; i += 3) {
    final f = () {
      j--;
      i++;
      return i * 100 + j;
    };
    number(f());
    number(i);
    number(j);
  }
  // expect: 109
  // expect: 1
  // expect: 9
  // expect: 508
  // expect: 5
  // expect: 8
  int Function()? last;
  var n = 0;
  while (n < 3) {
    var k = n * 10;
    k++;
    final old = last;
    last = () => k++ + (old == null ? 0 : old());
    n++;
  }
  show(last?.call()); // expect: 33
  show(last?.call()); // expect: 36
  do {
    var q = n;
    run(() => q++);
    number(q);
  } while (--n > 0);
  // expect: 4
  // expect: 3
  // expect: 2
  for (var i = 0; i < 2; i++) {
    int? u;
    show(u);
    run(() => u = i);
    show(u);
  }
  // expect: null
  // expect: 0
  // expect: null
  // expect: 1
  for (var i = 0; i < 4; i++) {
    if (i == 1) continue;
    final f = () => i;
    if (i == 3) break;
    number(f());
  }
  // expect: 0
  // expect: 2
}

void number(int n) => print(n);

void truth(bool b) => print(b);
