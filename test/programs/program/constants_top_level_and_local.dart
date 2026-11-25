import 'dart:io';

const a = 3, b = a * 2.5, c = a > 2;
void main() {
  const d = a ~/ 2;
  exit(c && b == 7.5 ? a * 10 + d : 0);
}
// exit: 31
