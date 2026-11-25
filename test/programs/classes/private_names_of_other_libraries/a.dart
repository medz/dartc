class A {
  int _f() => 1;
  int f() => _f();
  int n = 4;
}

A make() => A();
