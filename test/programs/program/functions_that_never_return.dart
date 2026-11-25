import 'dart:io';

Never stop(int x) => exit(x);
int f(bool b) => b ? 1 : stop(6);
int g(bool b) {
  if (b) return 2;
  stop(7);
}

void main() {
  f(true);
  g(true);
  final int x = g(false);
  f(false);
  exit(x);
}
// exit: 7
