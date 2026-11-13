import 'decimal.dart';
import 'remainder.dart';

@patch
class double {
  @patch
  static double? _nativeParse(String str, int start, int end) =>
      DoubleText.tryParse(str, start, end);
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
  String _toString() => DoubleText.shortest(this);
  @patch
  String _toStringAsFixed(int fractionDigits) =>
      DoubleText.fixed(this, fractionDigits);
  @patch
  String _toStringAsExponential(int fractionDigits) =>
      DoubleText.exponential(this, fractionDigits);
  @patch
  String _toStringAsPrecision(int fractionDigits) =>
      DoubleText.precision(this, fractionDigits);

  @patch
  double _modulo(double other) => floatingModulo(this, other);
  @patch
  double _remainder(double other) => floatingRemainder(this, other);
}
