import 'dart:io';

bool even(int n) => n == 0 || odd(n - 1);
bool odd(int n) {
  if (n == 0) return false;
  return even(n - 1);
}

void main() {
  exit(even(10) ? 1 : 2);
}
// exit: 1
