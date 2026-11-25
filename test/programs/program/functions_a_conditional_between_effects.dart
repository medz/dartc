import 'dart:io';

void f(int x) {
  exit(x);
}

void main() {
  1 > 2 ? f(1) : f(2);
}
// exit: 2
