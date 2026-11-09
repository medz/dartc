// ignore_for_file: control_flow_in_finally, unnecessary_type_name_in_constructor, use_primary_constructors

import 'effects.dart';

int asserted(int input) {
  assert(probe(input), tick(20));
  return tick(30);
}

int withoutMessage(bool condition) {
  assert(condition);
  return 40;
}

int throwingMessage(bool condition) {
  assert(condition, tick(-2));
  return tick(50);
}

int caught(int input) {
  try {
    assert(probe(input), tick(60));
    return tick(61);
  } catch (_) {
    return tick(62);
  } finally {
    tick(63);
  }
}

int finalizerOverride(bool condition) {
  try {
    assert(condition, tick(70));
    return 71;
  } finally {
    return tick(72);
  }
}

int closureCondition(int input) {
  assert(
    () {
      tick(80);
      return input > 0;
    }(),
    () {
      return tick(81);
    }(),
  );
  return tick(82);
}

class CheckedValue {
  final int value;
  CheckedValue(int input) : value = tick(90), assert(probe(input), tick(91)) {
    tick(92);
  }
}

int construct(int input) => CheckedValue(input).value;

class EarlyCheck {
  final int value;
  EarlyCheck(int input) : assert(probe(input), tick(100)), value = tick(101);
}

int constructEarly(int input) => EarlyCheck(input).value;

int typedCatch(int input) {
  try {
    assert(probe(input), tick(110));
    return tick(111);
  } on AssertionError {
    return tick(112);
  } on Error {
    return tick(113);
  }
}
