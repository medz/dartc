num add(num a, num b) => a + b;
num subtract(num a, num b) => a - b;
num multiply(num a, num b) => a * b;
double divide(num a, num b) => a / b;
int truncate(num a, num b) => a ~/ b;
num modulo(num a, num b) => a % b;
bool less(num a, num b) => a < b;
bool lessEqual(num a, num b) => a <= b;
bool greater(num a, num b) => a > b;
bool greaterEqual(num a, num b) => a >= b;
num negate(num a) => -a;
double negateDouble(double a) => -a;
double mixedAdd(int a, double b) => a + b;
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
