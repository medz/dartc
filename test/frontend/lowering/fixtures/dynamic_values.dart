// ignore_for_file: prefer_interpolation_to_compose_strings, dead_code
import 'effects.dart';

dynamic identity(dynamic value) => value;
int typedReturn(dynamic value) => identity(value);
int consume(int first, int second) => first * 10 + second;

int localCast(dynamic value) {
  int result = identity(value);
  return result + tick(2);
}

int assignmentCast(dynamic value) {
  var result = 7;
  try {
    result = identity(value);
  } finally {
    tick(result);
  }
  return result;
}

int returnCast(dynamic value) {
  try {
    return identity(value);
  } finally {
    tick(8);
  }
}

int argumentCast(dynamic value) => consume(identity(value), tick(3));

class Slot() {
  int value = 0;
  set checked(int input) {
    tick(20);
    value = input;
  }

  void operator []=(int index, int input) {
    tick(30 + index);
    value = input;
  }
}

int setterCast(dynamic value) {
  final slot = Slot();
  slot.checked = identity(value);
  return slot.value;
}

int fieldCast(dynamic value) {
  final slot = Slot();
  slot.value = identity(value);
  return slot.value;
}

int indexKeyCast(dynamic value) {
  final slot = Slot();
  slot[identity(value)] = tick(4);
  return slot.value;
}

int indexValueCast(dynamic value) {
  final slot = Slot();
  slot[tick(4)] = identity(value);
  return slot.value;
}

int listElementCast(dynamic value) {
  final values = <int>[identity(value), tick(5)];
  return values[0] + values[1];
}

int mapKeyCast(dynamic value) {
  final values = <int, int>{identity(value): tick(6)};
  return values.length;
}

int mapValueCast(dynamic value) {
  final values = <int, int>{tick(6): identity(value), tick(7): tick(8)};
  return values.length;
}

int genericCast(dynamic value) {
  T get<T>(dynamic input) => input;
  return get<int>(value) + tick(9);
}

int dynamicStorage(dynamic value) {
  dynamic copy = identity(value);
  Object? erased = copy;
  return erased == value ? 1 : 0;
}

int conditionIf(dynamic value) {
  if (identity(value)) return tick(1);
  return tick(2);
}

int conditionWhile(dynamic value) {
  while (identity(value)) {
    return tick(3);
  }
  return tick(4);
}

int conditionFor(dynamic value) {
  for (; identity(value);) {
    return tick(3);
  }
  return tick(4);
}

int conditionDo(dynamic value) {
  do {
    tick(5);
    if (identity(value)) return 1;
  } while (identity(value));
  return 0;
}

int conditionTernary(dynamic value) => identity(value) ? tick(1) : tick(2);
int conditionAnd(dynamic value) => identity(value) && probe(3) ? 1 : 0;
int conditionOr(dynamic value) => identity(value) || probe(3) ? 1 : 0;
int conditionNot(dynamic value) => !identity(value) ? tick(1) : tick(2);

int parameterAssignment(dynamic value) {
  int assign(int result) {
    result = value;
    return result;
  }

  return assign(7);
}

int capturedAssignment(dynamic value) {
  var result = 7;
  void assign() {
    result = value;
  }

  try {
    assign();
  } finally {
    tick(result);
  }
  return result;
}

class Arguments(final int first, final int second) {
  static int call(int first, int second) => first * 10 + second;
}

int constructorArgument(dynamic value) {
  final result = Arguments(identity(value), tick(3));
  return result.first + result.second;
}

int staticArgument(dynamic value) => Arguments.call(identity(value), tick(3));
int functionArgument(dynamic value) {
  final int Function(int, int) function = consume;
  return function(identity(value), tick(3));
}

int intOperator(dynamic value) {
  final result = 2 + identity(value);
  return result is int ? result : 99;
}

int stringOperator(dynamic value) => ('a' + identity(value)) == 'abad' ? 1 : 0;

class Operand() {
  int operator +(int value) {
    tick(20);
    return value;
  }
}

int userOperator(dynamic value) => Operand() + identity(value);
int conditionAndRight(dynamic value) =>
    probe(3) && identity(value) ? tick(1) : tick(2);
int conditionOrRight(dynamic value) =>
    !probe(3) || identity(value) ? tick(1) : tick(2);
int conditionAndSkipped(dynamic value) =>
    !probe(3) && identity(value) ? tick(1) : tick(2);
int conditionOrSkipped(dynamic value) =>
    probe(3) || identity(value) ? tick(1) : tick(2);

Never returnNever(dynamic value) {
  try {
    return identity(value);
  } finally {
    tick(8);
  }
}

int neverReturn(dynamic value) => returnNever(value);
int acceptNever(Never value, int second) => second;
int neverArgument(dynamic value) {
  try {
    return acceptNever(identity(value), tick(3));
  } finally {
    tick(8);
  }
}

int neverElement(dynamic value) {
  try {
    final values = <Never>[identity(value), throw tick(3)];
    return values.length;
  } finally {
    tick(8);
  }
}

int genericBoundTypes(dynamic value) {
  T defaultBound<T>(T input) => input;
  T objectBound<T extends Object?>(T input) => input;
  T dynamicBound<T extends dynamic>(T input) => input;
  Object function = 0 == value
      ? defaultBound
      : 1 == value
      ? objectBound
      : dynamicBound;
  var result = 0;
  if (function is T Function<T>(T)) result += 1;
  if (function is T Function<T extends Object?>(T)) result += 2;
  if (function is T Function<T extends dynamic>(T)) result += 4;
  return result;
}

class BoundBox<T>(final T value);
typedef DynamicBox<T extends dynamic> = BoundBox<T>;
typedef ObjectBox<T extends Object?> = BoundBox<T>;
int genericAliasEquality(dynamic value) {
  final dynamicAlias = DynamicBox.new;
  final objectAlias = ObjectBox.new;
  var result = 0;
  if (dynamicAlias == BoundBox.new) result += 1;
  if (objectAlias == BoundBox.new) result += 2;
  if (dynamicAlias == objectAlias) result += 4;
  if (dynamicAlias<int> == BoundBox<int>.new) result += 8;
  if (objectAlias<int> == BoundBox<int>.new) result += 16;
  if (identical(dynamicAlias, BoundBox.new)) result += 32;
  if (identical(objectAlias, BoundBox.new)) result += 64;
  if (identical(dynamicAlias, objectAlias)) result += 128;
  return result;
}

int contextualRecord(dynamic value) {
  final (int a, int b) result = (value, tick(2));
  return result.$1 + result.$2;
}
