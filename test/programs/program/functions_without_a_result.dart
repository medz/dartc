import 'dart:io';

void f(int x) {
  if (x > 3) return;
  exit(x);
}

void g() => f(2);
void main() {
  f(5);
  g();
}
// exit: 2
