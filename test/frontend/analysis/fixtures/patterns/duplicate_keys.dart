import '../numeric_constants.dart';

const same = integer > floating;

int classify(Map<bool, int> value) => switch (value) {
  {true: final a, same: final b} => a + b,
  _ => 0,
};
