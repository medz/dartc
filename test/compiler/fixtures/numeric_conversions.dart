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
