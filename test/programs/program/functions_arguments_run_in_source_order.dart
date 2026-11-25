import 'dart:io';

int f({required int a, required int b}) => a * 10 + b;
void main() {
  var n = 1;
  exit(f(b: n++, a: n++));
}
// exit: 21
