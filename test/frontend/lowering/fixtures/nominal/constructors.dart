import '../effects.dart' as effects;
import 'other.dart' as other;

abstract interface class Mark();

class Base.named(int value, {int bias = 10}) {
  final int first = effects.tick(2);
  this {
    effects.tick(value + bias);
  }

  factory pick(int n) => n == 0 ? Base.named(0) : Item.redirect(n);

  static int positive(int n) => effects.tick(n);
}

class Item(int value) extends Base implements Mark {
  final int own = effects.tick(3);
  final int n;
  this
    : n = effects.tick(value),
      super.named(effects.tick(4), bias: effects.tick(5)) {
    effects.tick(6);
  }
  new redirect(int n) : this(effects.tick(n));
}

final class Primary(final int n, {super.bias = 7}) extends Base {
  this : super.named(effects.tick(n)) {
    effects.tick(8);
  }
}

class Inherited(super.value, {super.bias}) extends Base {
  this : super.named();
}

int inheritedDefault(int n) => Inherited(n).first;

sealed class Choice();

class First() extends Choice;

class Second() extends Choice;

int exhaustiveChoice(bool first) {
  final Choice choice = first ? First() : Second();
  return switch (choice) {
    First() => 1,
    Second() => 2,
  };
}

sealed class Outcome<T>();
class Present<T>(final T value) extends Outcome<T>;
class Missing<T>() extends Outcome<T>;

int exhaustiveGeneric(int value) {
  final Outcome<int> outcome = value > 0 ? Present(value) : Missing();
  return switch (outcome) {
    Present<int>(:final value) => value,
    Missing<int>() => 0,
  };
}

int construct(int n) {
  try {
    final Base item = Base.pick(Base.positive(n));
    if (item is Mark) return 1;
    return 0;
  } on Error {
    return 2;
  }
}

bool primary(int n) => Primary(n) == Primary(n);

int separateLibraries(bool local) {
  final Object item = local ? Item(1) : other.Item();
  return switch (item) {
    other.Item _ => 3,
    Mark _ => 4,
    _ => 5,
  };
}

int typedException(bool first) {
  try {
    throw first ? First() : Second();
  } on First {
    return 1;
  } on Choice {
    return 2;
  }
}
