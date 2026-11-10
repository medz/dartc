import 'dart:ffi';

import 'package:dartc/interop.dart';

class Token(final int value);

Never fail(Object value) => throw value;

void allocate(int count) {
  for (var i = 0; i < count; i++) {
    Token(i);
  }
}

@Export<Int64 Function(Int64, Int64, Pointer<Int64>)>()
int cleanup(int mode, int count, Pointer<Int64> effects) {
  final token = Token(7);
  try {
    try {
      effects.value = 1;
      if (mode == 0) return 100;
      fail(token);
    } catch (_) {
      effects.value = effects.value * 10 + 2;
      allocate(count);
      if (mode == 1) rethrow;
      if (mode == 2) return 200;
      throw token;
    } finally {
      effects.value = effects.value * 10 + 3;
      // ignore: control_flow_in_finally
      if (mode == 4) return 400;
      if (mode == 5) throw token;
    }
  } catch (_) {
    effects.value = effects.value * 10 + 4;
    return 307;
  } finally {
    effects.value = effects.value * 10 + 5;
  }
}

class FailingConstruction(int value, Pointer<Int64> effects) {
  this {
    effects.value += 1;
    fail(value);
  }
}

@Export<Int64 Function(Int64, Pointer<Int64>)>()
int constructorFailure(int value, Pointer<Int64> effects) {
  try {
    FailingConstruction(value, effects);
  } catch (_) {
    return effects.value;
  }
  return -1;
}

int recover(int value) {
  try {
    fail(value);
  } catch (_) {
    return value + 1;
  }
}

@Export<Int64 Function(Int64)>()
int recoveredCalls(int value) => recover(value) + recover(value + 1);

int choose(int value) {
  if (value < 0) throw value;
  return value * 2;
}

@Export<Int64 Function(Int64)>()
int checkedCall(int value) {
  try {
    return choose(value) + 1;
  } catch (_) {
    return -1;
  }
}

double chooseDouble(double value) {
  if (value < 0) throw value;
  return value + 0.25;
}

@Export<Double Function(Double)>()
double checkedDouble(double value) {
  try {
    return chooseDouble(value) * 2;
  } catch (_) {
    return -3.5;
  }
}

void main() => fail(7);
