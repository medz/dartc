import 'dart:io';

double half(double x) => x / 2;
double sum(double a, int b) => a + b;
void main() {
  exit(sum(half(5), 2) == 4.5 ? 1 : 0);
}
// exit: 1
