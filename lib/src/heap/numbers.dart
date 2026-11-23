// What numbers do where their kind is known only when the program runs.
import 'machine.dart';

/// Whether [self] equals any object.
bool intEquals(int self, Object other) {
  if (other is int) return self == other;
  return other is double && self.toDouble() == other;
}

bool doubleEquals(double self, Object other) {
  if (other is double) return self == other;
  return other is int && self == other.toDouble();
}

/// Whether [a] and [b] are the same object; numbers are by their bits.
bool sameObjects(Object? a, Object? b) {
  if (a is int) return b is int && a == b;
  if (a is double) return b is double && _sameDoubles(a, b);
  return isSame(a, b);
}

bool _sameDoubles(double a, double b) {
  if (a != b) return a != a && b != b;
  return a != 0 || 1 / a == 1 / b;
}

double numToDouble(num value) {
  if (value is double) return value;
  return value is int ? value.toDouble() : 0.0;
}

int numToInt(num value) {
  if (value is int) return value;
  return numToDouble(value).toInt();
}

num numNegate(num value) {
  if (value is int) return -value;
  return -numToDouble(value);
}

num numAdd(num a, num b) {
  if (a is int && b is int) return a + b;
  return numToDouble(a) + numToDouble(b);
}

num numSubtract(num a, num b) {
  if (a is int && b is int) return a - b;
  return numToDouble(a) - numToDouble(b);
}

num numMultiply(num a, num b) {
  if (a is int && b is int) return a * b;
  return numToDouble(a) * numToDouble(b);
}

double numDivide(num a, num b) => numToDouble(a) / numToDouble(b);

int numTruncate(num a, num b) {
  if (a is int && b is int) return a ~/ b;
  return numToDouble(a) ~/ numToDouble(b);
}

num numModulo(num a, num b) {
  if (a is int && b is int) return a % b;
  return numToDouble(a) % numToDouble(b);
}

bool numLess(num a, num b) {
  if (a is int && b is int) return a < b;
  return numToDouble(a) < numToDouble(b);
}

bool numLessOrEqual(num a, num b) {
  if (a is int && b is int) return a <= b;
  return numToDouble(a) <= numToDouble(b);
}
