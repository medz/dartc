import '../runtime/entropy.dart' as entropy;
import '../runtime/memory.dart';

import 'math_functions.dart' as functions;

@patch
class _Random {
  @patch
  static int _initialSeed() =>
      _setupSeed(entropy.randomBytes(8) ?? Memory.clock());
}

@patch
class _SecureRandom {
  @patch
  static int _getBytes(int count) =>
      entropy.randomBytes(count) ??
      (throw UnsupportedError(
        'No source of cryptographically secure random numbers available.',
      ));
}

@patch
double _doublePow(double base, double exponent) =>
    functions.pow(base, exponent);

@patch
double _atan2(double a, double b) => functions.atan2(a, b);

@patch
double _sin(double x) => functions.sin(x);

@patch
double _cos(double x) => functions.cos(x);

@patch
double _tan(double x) => functions.tan(x);

@patch
double _asin(double x) => functions.asin(x);

@patch
double _acos(double x) => functions.acos(x);

@patch
double _atan(double x) => functions.atan(x);

@patch
double _exp(double x) => functions.exp(x);

@patch
double _log(double x) => functions.log(x);
