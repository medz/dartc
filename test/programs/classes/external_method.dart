class A {
  external void f(); // error 20: Not supported yet: a function without a body.
}

void main() {
  A().f();
}
