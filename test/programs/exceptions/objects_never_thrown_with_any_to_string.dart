int n = 0;

class A {
  String toString() => "$n";
}

class B {}

void main() {
  print(A()); // expect: 0
  throw B();
}
// stderr: Unhandled exception:
// stderr: Instance of 'B'
// exit: 255
