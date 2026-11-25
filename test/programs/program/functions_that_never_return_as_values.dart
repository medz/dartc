import 'dart:io';

Never stop(int x) => exit(x);
int f(bool b) => b ? 1 : stop(6);
void main() {
  final int x = f(true) + f(false);
  exit(x);
}
// exit: 6
