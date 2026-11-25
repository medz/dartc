class A {
  static int _x = 1;
  static int get x {
    print('get');
    return _x;
  }

  static set x(int value) {
    print('set');
    _x = value;
  }

  static A? _a;
  static A? get a => _a;
  static set a(A? value) {
    _a = value;
  }

  int f() {
    x++;
    return x;
  }
}

void main() {
  number(A.x);
  // expect: get
  // expect: 1
  A.x = 5; // expect: set
  A.x--;
  // expect: get
  // expect: set
  number(A.x);
  // expect: get
  // expect: 4
  number(A().f());
  // expect: get
  // expect: set
  // expect: get
  // expect: 5
  truth(A.a == null); // expect: true
  A.a ??= A();
  truth(A.a == A.a); // expect: true
}

void number(int n) => print(n);

void truth(bool b) => print(b);
