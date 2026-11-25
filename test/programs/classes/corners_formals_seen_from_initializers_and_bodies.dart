class A {
  int x, y, z = 0;
  A(this.x) : y = x + 1 {
    x = 10;
    z = x + y;
  }
}

class B extends A {
  int w;
  B(super.x) : w = x * 100 {
    x++;
  }
}

void main() {
  final a = A(1);
  number(a.x); // expect: 10
  number(a.y); // expect: 2
  number(a.z); // expect: 12
  final b = B(2);
  number(b.w); // expect: 200
  number(b.x); // expect: 11
}

void number(int n) => print(n);
