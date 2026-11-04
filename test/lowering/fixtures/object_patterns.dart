// Deliberately exercise total patterns and cross-type user-defined equality.
// ignore_for_file: dead_code, unrelated_type_equality_checks

import 'effects.dart';

class Sample(final int seed) {
  int get first => tick(seed);
  int get second => tick(seed + 10);
  Object? get maybe => seed == 0 ? null : tick(seed + 20);
  int plus(int value) => seed + value;
  Sample get self {
    tick(50);
    return this;
  }
}

class Derived(super.seed) extends Sample {
  @override
  int get first => tick(seed + 1);
}

int orderedObject(int seed, bool derived) {
  Object value = derived ? Derived(seed) : Sample(seed);
  if (value case Sample(second: var second, first: var first)
      when probe(first)) {
    return second + first;
  }
  return -1;
}

int shortObject(int seed) {
  if (Sample(seed) case Sample(first: > 0, second: var second)) return second;
  return -1;
}

int wildcardObject(int seed) {
  if (Sample(seed) case Sample(first: _, second: int _)) return 1;
  return 0;
}

int nullableObject(int seed) {
  if (Sample(seed) case Sample(maybe: int value?)) return value;
  return -1;
}

int assertObject(int seed) {
  try {
    if (Sample(seed) case Sample(maybe: var value!)) return value as int;
  } catch (_) {
    return tick(99);
  }
  return -1;
}

int declareObject(int seed) {
  final Sample(:first, :second) = Sample(seed);
  return first + second;
}

int assignObject(int seed) {
  var first = 100;
  var second = 200;
  try {
    Sample(second: first, first: second) = Sample(seed);
  } catch (_) {
    return first + second;
  }
  return first + second;
}

int methodObject(int seed) {
  final Sample(plus: f) = Sample(seed);
  return f(3);
}

int mismatchObject(Object? value) => switch (value) {
  Sample(first: var first) => first,
  int() => 1,
  String() => 2,
  _ => 0,
};

int nestedObject(int seed) {
  if ((Sample(seed), 3) case (Sample(first: var a), var b)) return a + b;
  return -1;
}

int alternativeObject(int seed) {
  if (Sample(seed)
      case Sample(first: 0, second: var v) || Sample(first: var v)) {
    return v;
  }
  return -1;
}

int andObject(int seed) {
  if (Sample(seed) case Sample(first: > 0) && Sample(first: var v)) return v;
  return -1;
}

int nestedAlternativeObject(int seed) {
  if ((Sample(seed), 0)
      case (Sample(first: 0, second: var v), _) || (Sample(first: var v), _)) {
    return v;
  }
  return -1;
}

int switchObject(int seed) => switch (Sample(seed)) {
  Sample(first: var v) when probe(0) => v,
  Sample(first: 0, second: var v) => v,
  Sample(first: var v) => v,
};

int switchStatementObject(int seed) {
  switch (Sample(seed)) {
    case Sample(first: var v) when probe(0):
      return v;
    case Sample(first: 0, second: var v):
      return v;
    case Sample(first: var v):
      return v;
  }
}

int castObject(int seed) {
  try {
    if (Sample(seed) case Sample(maybe: var v as int)) return v;
  } on TypeError {
    return tick(99);
  }
  return -1;
}

int typeAlternativeObject(int seed, bool derived) {
  Object value = derived ? Derived(seed) : Sample(seed);
  if (value case Derived(first: 0, second: var v) || Sample(first: var v)) {
    return v;
  }
  return -1;
}

int nestedGetterObject(int seed) {
  if (Sample(seed)
      case Sample(self: Sample(first: 0, second: var v)) ||
          Sample(self: Sample(first: var v))) {
    return v;
  }
  return -1;
}

int loopObject(int seed) {
  var result = 0;
  for (var i = 0; i < 3; i++) {
    if (Sample(seed + i) case Sample(first: > 0) && Sample(first: var v)) {
      result += v;
    }
  }
  return result;
}

class MutableSample(var int value) {
  int get first => tick(value);
  bool change() {
    value += 10;
    return false;
  }
}

int guardedMutationObject(int seed) {
  final subject = MutableSample(seed);
  final result = switch (subject) {
    MutableSample(first: var v) when subject.change() => v,
    MutableSample(first: var v) => v,
  };
  return result + subject.value;
}

class WideSample(final int value) {
  Object get first => tick(value);
}

class NarrowSample(super.value) extends WideSample {
  @override
  int get first => tick(value + 1);
}

int narrowedGetterObject(int seed) {
  WideSample subject = NarrowSample(seed);
  return switch (subject) {
    WideSample(first: int v) when probe(0) => v,
    NarrowSample(first: var v) => v,
    _ => -1,
  };
}

int separateMatchesObject(int seed) {
  final subject = MutableSample(seed);
  var result = switch (subject) {
    MutableSample(first: > 0) && MutableSample(first: var v) => v,
    _ => 0,
  };
  subject.change();
  result += switch (subject) {
    MutableSample(first: > 0) && MutableSample(first: var v) => v,
    _ => 0,
  };
  return result;
}

class Comparator(var int value) {
  bool operator >(int other) {
    tick(70 + other);
    return value > other;
  }

  bool operator <(int other) {
    tick(80 + other);
    return value < other;
  }

  @override
  bool operator ==(Object other) {
    tick(90);
    return value == other;
  }

  @override
  int get hashCode => value;
  bool change() {
    value += 10;
    return false;
  }
}

int relationalAndObject(int seed) {
  if (Comparator(seed) case > 0 && > 0) return 1;
  return 0;
}

int relationalOrObject(int seed) {
  if (Comparator(seed) case > 0 || > 0) return 1;
  return 0;
}

int equalityComplementObject(int seed) {
  if (Comparator(seed) case == 0 || != 0) return 1;
  return 0;
}

int distinctRelationalObject(int seed) => switch (Comparator(seed)) {
  > 0 && < 2 => 1,
  > 1 => 2,
  > 0 => 3,
  _ => 0,
};

int guardedRelationalObject(int seed) {
  final subject = Comparator(seed);
  return switch (subject) {
    > 0 when subject.change() => 1,
    > 0 => 2,
    _ => 0,
  };
}

int canonicalRelationalObject(int seed) {
  if (Comparator(seed) case > (1 + 1) || > 2) return 1;
  return 0;
}

int relationalStatementObject(int seed) {
  switch (Comparator(seed)) {
    case > 0 when probe(0):
      return 1;
    case > 0:
      return 2;
    default:
      return 0;
  }
}

int recordEqualityObject(int seed) {
  if (Comparator(seed) case == const (1, 2) || == const (1, 2)) return 1;
  return 0;
}

int distinctEqualityObject(int seed) {
  if (Comparator(seed) case == 0.0 || == -0.0 || == 0) return 1;
  return 0;
}

int nanEqualityObject(int seed) {
  if (Comparator(seed) case == double.nan || == double.nan) return 1;
  return 0;
}

int receiverPathsObject(int seed) {
  final subject = Comparator(seed);
  if ((subject, subject) case (> 0 && > 0, > 0 && > 0)) return 1;
  return 0;
}
