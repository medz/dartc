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

sealed class Choice();

class First() extends Choice;

class Second() extends Choice;

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
