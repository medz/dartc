// The SDK treats opposite as true after rounding the mixed comparison.
// ignore_for_file: non_exhaustive_switch_expression, non_exhaustive_switch_statement, unreachable_switch_case, equal_keys_in_map_pattern

import '../numeric_constants.dart';

const opposite = integer == floating;

int boolean(bool value) => switch (value) {
  true => 1,
  opposite => 2,
};

int nullable(bool? value) => switch (value) {
  null => 0,
  true => 1,
  opposite => 2,
};

int pair(bool a, bool b) => switch ((a, b)) {
  (true, _) => 1,
  (opposite, true) => 2,
  (opposite, opposite) => 3,
};

int statement(bool value) {
  var result = 0;
  switch (value) {
    case true:
      result = 1;
    case opposite:
      result = 2;
  }
  return result;
}

int returning(bool value) {
  switch (value) {
    case true:
      return 1;
    case opposite:
      return 2;
  }
}

sealed class Shape();
final class Box(final bool value) extends Shape;
final class Other() extends Shape;

int sealed(bool boxed, bool value) {
  final Shape shape = boxed ? Box(value) : Other();
  return switch (shape) {
    Box(value: true) => 1,
    Box(value: opposite) => 2,
    Other() => 3,
  };
}

int keys() => switch (<bool, int>{true: 3, false: 4}) {
  {true: final a, opposite: final b} => a + b,
  _ => 0,
};

enum const Direction(final bool forward) {
  next(integer > floating),
  previous(opposite),
}

int enumeration(bool forward) {
  final direction = forward ? Direction.next : Direction.previous;
  return switch (direction) {
    Direction.next => direction.forward ? 1 : -1,
    Direction.previous => direction.forward ? -2 : 2,
  };
}

int enumRecord(bool forward, bool flag) =>
    switch ((forward ? Direction.next : Direction.previous, flag)) {
      (Direction.next, _) => 1,
      (Direction.previous, true) => 2,
      (Direction.previous, opposite) => 3,
    };

enum const Choice<T>(final T value) {
  number<int>(1),
  text<String>('text'),
}

int genericEnum() => switch (Choice.number) {
  Choice.number => 7,
};
