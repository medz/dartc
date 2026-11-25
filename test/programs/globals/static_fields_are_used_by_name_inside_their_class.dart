class A {
  static int n = 1;
  void up() {
    n++;
    this.other();
  }

  void other() {}
}

class B extends A {
  void down() {
    A.n -= 5;
  }
}

void main() {
  final b = B();
  b.up();
  b.up();
  b.down();
  number(A.n); // expect: -2
}

void number(int n) => print(n);
