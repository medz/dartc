import 'dart:io';

int f(int a, [int b = 2, int c = 3]) => a * 100 + b * 10 + c;
int g({required int a, int b = 7, double c = 1}) => c == 1 ? a * 10 + b : 0;
void main() {
  exit(f(1) + f(1, 5) + f(1, 5, 6) + g(b: 1, a: 2) + g(a: 3));
}
// exit: 234
