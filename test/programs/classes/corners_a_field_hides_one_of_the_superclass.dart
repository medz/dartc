class A {
  int x = 1;
  int a() => x;
}

class B extends A {
  @override
  int x = 2;
  int up() => super.x;
  void set() {
    super.x = 7;
    super.x += 2;
    super.x++;
  }
}

void main() {
  final b = B();
  number(b.x); // expect: 2
  number(b.a()); // expect: 2
  number(b.up()); // expect: 1
  b.set();
  number(b.x); // expect: 2
  number(b.up()); // expect: 10
}

void number(int n) => print(n);
