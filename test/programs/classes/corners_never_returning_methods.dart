import 'dart:io';

class A {
  Never stop(int n) {
    number(n);
    exit(n);
  }

  int f(bool b) => b ? 1 : stop(7);
}

void main() {
  final a = A();
  number(a.f(true)); // expect: 1
  number(a.f(false)); // expect: 7
  print('no');
}

void number(int n) => print(n); // exit: 7
