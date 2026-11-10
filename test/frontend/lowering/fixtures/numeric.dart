num add(num a, num b) => a + b;
num subtract(num a, num b) => a - b;
num multiply(num a, num b) => a * b;
double divide(num a, num b) => a / b;
int truncate(num a, num b) => a ~/ b;
num modulo(num a, num b) => a % b;
num remainder(num a, num b) => a.remainder(b);
int integerRemainder(int a, int b) => a.remainder(b);
int userRemainder() => const UserNumber().remainder(7);
int extensionRemainder() => UserConversion(3).remainder(7);
bool less(num a, num b) => a < b;
bool lessEqual(num a, num b) => a <= b;
bool greater(num a, num b) => a > b;
bool greaterEqual(num a, num b) => a >= b;
num negate(num a) => -a;
double negateDouble(double a) => -a;
double mixedAdd(int a, double b) => a + b;
double convertNumber(num value) => value.toDouble();
int convertInteger(num value, int mode) => switch (mode) {
  0 => value.toInt(),
  1 => value.truncate(),
  2 => value.floor(),
  3 => value.ceil(),
  _ => value.round(),
};
int userIntegerConversion() => const UserNumber().toInt();
int extensionIntegerConversion() => UserConversion(3).toInt();
double userConversion() => const UserNumber().toDouble();
double extensionConversion() => UserConversion(3).toDouble();

class const UserNumber() {
  int toInt() => 12;
  double toDouble() => 7.5;
  int remainder(int value) => value + 5;
}

extension UserConversion on int {
  int toInt() => 13;
  double toDouble() => 8.5;
  int remainder(int value) => value + 6;
}

double doubleModulo(double a, num b) => a % b;
num compound(num a, num b) {
  a += b;
  a *= b;
  a -= b;
  return a;
}

num increment(num a) {
  final before = a++;
  return before + ++a;
}

int caughtTruncate(num a, num b) {
  try {
    return a ~/ b;
  } catch (_) {
    return 12345;
  }
}

num caughtModulo(num a, num b) {
  try {
    return a % b;
  } catch (_) {
    return 12345;
  }
}
