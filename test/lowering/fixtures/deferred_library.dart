import 'effects.dart';

const constant = 7;
int value = 0;
int add(int n) => n + 10;
T echo<T>(T value) => value;
int get read => tick(20);
set write(int n) {
  value = tick(n);
}

int Function(int) get function {
  tick(21);
  return add;
}

class C(final int value) {
  new named(int value) : this(value);
  static const constant = 32;
  static int method(int n) => n + 30;
  static int get read => tick(31);
  static set write(int n) {
    tick(n);
  }
}

extension type E(int value);
