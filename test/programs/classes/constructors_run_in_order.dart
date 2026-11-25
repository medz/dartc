class A {
  int a = trace(1);
  final int b;
  int c;
  A(this.b, {int x = 5}) : c = trace(x) {
    print('A');
    show();
  }
  void show() => print('A.show');
}

class B extends A {
  int d = trace(2);
  int e;
  B(int q, {super.x}) : e = trace(q), super(trace(q + 1)) {
    print('B');
  }
  B.two() : this(trace(9));
  B.three(super.b) : e = 7;
  @override
  void show() {
    number(d);
    number(e);
    number(b);
    number(c);
    super.show();
  }
}

void main() {
  B(7, x: 8);
  // expect: 2
  // expect: 7
  // expect: 8
  // expect: 1
  // expect: 8
  // expect: A
  // expect: 2
  // expect: 7
  // expect: 8
  // expect: 8
  // expect: A.show
  // expect: B
  B.two();
  // expect: 9
  // expect: 2
  // expect: 9
  // expect: 10
  // expect: 1
  // expect: 5
  // expect: A
  // expect: 2
  // expect: 9
  // expect: 10
  // expect: 5
  // expect: A.show
  // expect: B
  B.three(4).show();
  // expect: 2
  // expect: 1
  // expect: 5
  // expect: A
  // expect: 2
  // expect: 7
  // expect: 4
  // expect: 5
  // expect: A.show
  // expect: 2
  // expect: 7
  // expect: 4
  // expect: 5
  // expect: A.show
}

void number(int n) => print(n);

int trace(int n) {
  print(n);
  return n;
}
