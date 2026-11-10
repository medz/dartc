import 'dart:ffi';

import 'package:dartc/interop.dart';

@Export<Int64 Function(Double, Int64)>()
int convertDouble(double value, int mode) => switch (mode) {
  0 => value.toInt(),
  1 => value.truncate(),
  2 => value.floor(),
  3 => value.ceil(),
  _ => value.round(),
};

@Export<Int64 Function(Int64, Int64)>()
int convertInt(int value, int mode) => switch (mode) {
  0 => value.toInt(),
  1 => value.truncate(),
  2 => value.floor(),
  3 => value.ceil(),
  _ => value.round(),
};

int _number(num value, int mode) => switch (mode) {
  0 => value.toInt(),
  1 => value.truncate(),
  2 => value.floor(),
  3 => value.ceil(),
  _ => value.round(),
};

@Export<Int64 Function(Double, Int64)>()
int boxedDouble(double value, int mode) => _number(value, mode);

@Export<Int64 Function(Int64, Int64)>()
int boxedInt(int value, int mode) => _number(value, mode);

@Export<Int64 Function(Double, Int64, Int64)>()
int conversionFailure(double value, int mode, int boxed) {
  final state = _State();
  try {
    if (boxed == 0) {
      convertDouble(state.next(value), mode);
    } else {
      _number(state.next(value), mode);
    }
    state.log = state.log * 10 + 2;
  } on UnsupportedError catch (error) {
    if (error.message is! String || error.runtimeType != UnsupportedError) {
      return -1;
    }
    state.log = state.log * 10 + 3;
  } finally {
    state.log = state.log * 10 + 4;
  }
  return state.log;
}

@Export<Int64 Function(Double, Int64)>()
int savedMessage(double value, int count) {
  UnsupportedError? first;
  for (var i = 0; i < count; i++) {
    try {
      value.toInt();
    } on UnsupportedError catch (error) {
      first ??= error;
    }
  }
  return first?.message is String ? 1 : 0;
}

@Export<Int64 Function(Int64)>()
int checkedNonnegative(int value) {
  try {
    return RangeError.checkNotNegative(value);
  } on RangeError catch (error) {
    if (error.message is! String ||
        (error.start as int) != 0 ||
        error.end != null) {
      return -77;
    }
    return (error.invalidValue as int) - 1;
  }
}

class _State() {
  int log = 0;
  double next(double value) {
    log = log * 10 + 1;
    return value;
  }
}

@Export<Double Function(Double, Int64)>()
double roundDoubleToDouble(double value, int mode) => switch (mode) {
  0 => value.truncateToDouble(),
  1 => value.floorToDouble(),
  2 => value.ceilToDouble(),
  _ => value.roundToDouble(),
};

@Export<Double Function(Int64, Int64)>()
double roundIntToDouble(int value, int mode) => switch (mode) {
  0 => value.truncateToDouble(),
  1 => value.floorToDouble(),
  2 => value.ceilToDouble(),
  _ => value.roundToDouble(),
};

double _rounded(num value, int mode) => switch (mode) {
  0 => value.truncateToDouble(),
  1 => value.floorToDouble(),
  2 => value.ceilToDouble(),
  _ => value.roundToDouble(),
};

@Export<Double Function(Double, Int64)>()
double roundBoxedDouble(double value, int mode) => _rounded(value, mode);

@Export<Double Function(Int64, Int64)>()
double roundBoxedInt(int value, int mode) => _rounded(value, mode);

@Export<Int64 Function(Double, Int64)>()
int roundingEffects(double value, int mode) {
  final state = _State();
  _rounded(state.next(value), mode);
  return state.log * 10 + 2;
}

int _quotient<T extends num>(T left, T right) => left ~/ right;
int _leftQuotient(num left, int right) => left ~/ right;
int _rightQuotient(int left, num right) => left ~/ right;

@Export<Int64 Function(Double, Double, Int64, Int64, Int64)>()
int truncateDivide(double left, double right, int i, int j, int mode) =>
    switch (mode) {
      0 => left ~/ right,
      1 => left ~/ j,
      2 => i ~/ right,
      3 => _quotient(left, right),
      4 => _quotient(left, j),
      5 => _quotient(i, right),
      6 => _quotient(i, j),
      7 => _leftQuotient(left, j),
      8 => _rightQuotient(i, right),
      _ => _leftQuotient(i, j) + _rightQuotient(i, j),
    };

@Export<Int64 Function(Double, Double, Int64)>()
int quotientFailure(double left, double right, int boxed) {
  final state = _State();
  try {
    if (boxed == 0) {
      state.next(left) ~/ state.next(right);
    } else {
      _quotient(state.next(left), state.next(right));
    }
    state.log = state.log * 10 + 2;
  } on UnsupportedError {
    state.log = state.log * 10 + 3;
  } finally {
    state.log = state.log * 10 + 4;
  }
  return state.log;
}

@Export<Int64 Function(Int64, Int64)>()
int integerQuotientFailure(int left, int right) {
  try {
    return _quotient(left, right);
  } on UnsupportedError catch (error) {
    // Verify the SDK subtype still caught through UnsupportedError.
    // ignore: deprecated_member_use
    return error is IntegerDivisionByZeroException &&
            error.message is String &&
            error.stackTrace == null
        ? 77
        : -77;
  }
}
