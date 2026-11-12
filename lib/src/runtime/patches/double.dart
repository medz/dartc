import '../decimal.dart';
import '../numbers.dart';

@patch
class double {
  @patch
  String toString() => DoubleText.shortest(this);
  @override
  String toStringAsFixed(int fractionDigits) =>
      DoubleText.fixed(this, fractionDigits);
  @override
  String toStringAsExponential([int? fractionDigits]) =>
      DoubleText.exponential(this, fractionDigits);
  @override
  String toStringAsPrecision(int precision) =>
      DoubleText.precision(this, precision);
}

@patch
class _BigIntImpl {
  static final _DivRemResult _divisionResult = _DivRemResult();

  @patch
  static _DivRemResult get _cachedDivRemResult => _divisionResult;
}

@patch
class _Double {
  @patch
  double _modulo(double other) => floatingModulo(this, other);
  @patch
  double _remainder(double other) => floatingRemainder(this, other);
}
