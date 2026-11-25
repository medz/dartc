import 'dart:io';

int f(int a) {
  a += 1;
  a++;
  return a;
}

void main() {
  exit(f(5));
}
// exit: 7
