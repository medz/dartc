import '../effects.dart' as effects;
import 'other.dart' as other;

abstract interface class Shape() {
  int get axis;
  int measure(int n, {int x = 1, int y = 2});
}

class Box(var int value) implements Shape {
  @override
  int get axis => value;
  @override
  int measure(int n, {int y = 4, int x = 3, int extra = 8}) =>
      n + x * 10 + y + extra + axis;
  Box touch(int n) {
    effects.tick(n);
    return this;
  }
}

class Fancy(super.value) extends Box {
  @override
  int get axis => super.axis + 1;
  @override
  int measure(int n, {int extra = 7, int x = 6, int y = 5}) =>
      super.measure(n, x: x) + y + extra;
}

class Local() extends other.Hidden {
  int _read() => 4;
  int both() => via() * 10 + _read();
}

abstract interface class Consumer() {
  int accept(Object value);
}

class IntConsumer() implements Consumer {
  @override
  int accept(covariant int value) => effects.tick(value);
}

class Token(final int n) {
  @override
  bool operator ==(Object other) => other is Token && n == other.n;
  @override
  int get hashCode => n;
}

int selected(bool fancy, int n) {
  final Shape item = fancy ? Fancy(n) : Box(n);
  return item.measure(effects.tick(1)) +
      item.measure(y: effects.tick(2), effects.tick(3), x: effects.tick(n));
}

int? optionalMember(bool missing, int n) {
  final Box? b = missing ? null : Fancy(3);
  return b?.touch(effects.tick(n)).axis;
}

int checkedArgument(Object value) {
  final Consumer consumer = IntConsumer();
  try {
    return consumer.accept(value);
  } on TypeError {
    return 9;
  }
}

int hiddenMembers() => Local().both();
bool equalTokens(int x, int y) => (Token(x),) == (Token(y),);

class Promoted(final Object? _number) {
  int read() => _number is int ? _number + 1 : 0;
}

int promotedField(Object? n) => Promoted(n).read();
