import '../effects.dart' as effects;

class Cell(var int raw, var int? optional) {
  int get value {
    effects.tick(1);
    return raw;
  }

  set value(int n) {
    effects.tick(2);
    raw = n;
  }

  int? get maybe {
    effects.tick(3);
    return optional;
  }

  set maybe(int? n) {
    effects.tick(4);
    optional = n;
  }

  int operator [](int key) {
    effects.tick(10 + key);
    return raw;
  }

  void operator []=(int key, int n) {
    effects.tick(20 + key);
    raw = n;
  }

  Cell self(int mark) {
    effects.tick(mark);
    return this;
  }
}

class Sub(super.raw, super.optional) extends Cell {
  @override
  int get value => super.value + 1;
  @override
  set value(int n) {
    effects.tick(6);
    super.value = n + 1;
  }

  int bumpBase() => super.value++;
  int bumpIndex() => ++super[2];
}

int locations(int n, int mode) {
  final sub = Sub(7, null);
  final Cell c = sub;
  try {
    final v = switch (mode) {
      0 => c.self(8)[effects.tick(2)]++,
      1 => ++c.self(8).value,
      2 => c.self(8)[effects.tick(2)] += (c.raw = effects.tick(n)),
      3 => sub.bumpBase(),
      4 => sub.bumpIndex(),
      _ => c.self(8).value = effects.tick(n),
    };
    return v * 100 + c[0];
  } on Error {
    return c.raw;
  }
}

int optionalWrite(bool missing, int? initial, int n) {
  final source = Cell(1, initial);
  final Cell? maybe = missing ? null : source;
  final assigned = maybe?.self(5).maybe ??= effects.tick(n);
  final indexed = maybe?[effects.tick(7)] += effects.tick(n);
  return (assigned ?? 0) * 10 + (indexed ?? 0);
}

class NumberBox(final int v) {
  NumberBox operator +(int n) => NumberBox(v + effects.tick(n));
  NumberBox operator -() => NumberBox(-v);
  bool operator <(int n) => v < n;
}

int overloaded(int n) {
  var box = NumberBox(n);
  final before = box++;
  box += 2;
  if (-box case < 0) return before.v * 10 + box.v;
  return 0;
}

class Parent() {
  @override
  bool operator ==(Object other) {
    effects.tick(1);
    return true;
  }

  @override
  int get hashCode => 0;
}

class Child() extends Parent {
  @override
  bool operator ==(Object other) => false;
  @override
  int get hashCode => 0;
  bool differs(Object? other) => super != other;
}

bool compareSuper(Object? other) => Child().differs(other);

int integerOps(int a, int b) {
  try {
    final x = a < 0 ? (a % b) + (a ~/ b) : (a ~/ b) + (a % b);
    return (~x & 255) ^ ((a << b) | (a >> b)) ^ (a >>> b);
  } on Error {
    return effects.tick(9);
  } on Exception {
    return effects.tick(8);
  }
}

double quotient(int a, int b) => a / b;
