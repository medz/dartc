import 'dart:_heap/objects.dart'
    show
        arcCosine,
        arcSine,
        arcTangent,
        arcTangent2,
        cosine,
        exponential,
        logarithm,
        power,
        randomBits,
        sine,
        squareRoot,
        tangent;

@patch
double _doublePow(double base, double exponent) => power(base, exponent);
@patch
double _atan2(double a, double b) => arcTangent2(a, b);
@patch
double _sin(double x) => sine(x);
@patch
double _cos(double x) => cosine(x);
@patch
double _tan(double x) => tangent(x);
@patch
double _acos(double x) => arcCosine(x);
@patch
double _asin(double x) => arcSine(x);
@patch
double _atan(double x) => arcTangent(x);
@patch
double _sqrt(double x) => squareRoot(x);
@patch
double _exp(double x) => exponential(x);
@patch
double _log(double x) => logarithm(x);

@patch
class _Random {
  @patch
  static int _initialSeed() => randomBits() << 31 ^ randomBits();
}

@patch
class _SecureRandom {
  @patch
  static int _getBytes(int count) {
    var result = 0;
    for (var i = 0; i < count; i++) {
      result = result << 8 | randomBits() & 0xff;
    }
    return result;
  }
}
