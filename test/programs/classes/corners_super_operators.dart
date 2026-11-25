class A {
  int operator [](int i) => i;
  void operator []=(int i, int v) {
    number(i);
    number(v);
  }

  A operator +(A o) {
    print('+');
    return o;
  }

  bool operator <(A o) => true;
}

class B extends A {
  @override
  int operator [](int i) => super[i + 1] * 2;
  @override
  void operator []=(int i, int v) {
    super[i] = v + 1;
    super[i] += 3;
  }

  @override
  A operator +(A o) => super + o;
  void f() => truth(super < this);
}

void main() {
  final b = B();
  number(b[3]); // expect: 8
  b[4] = 5;
  // expect: 4
  // expect: 6
  // expect: 4
  // expect: 7
  truth(b + b == b);
  // expect: +
  // expect: true
  b.f(); // expect: true
}

void number(int n) => print(n);

void truth(bool b) => print(b);
