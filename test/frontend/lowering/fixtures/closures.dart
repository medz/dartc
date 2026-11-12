import 'effects.dart' as effects;

typedef Step = int Function(int);
typedef Read = int Function();

int localOrPattern(int value) {
  int Function() select(Object input) => switch (input) {
    (int number, _) || (_, int number) => () => number,
    _ => () => -1,
  };
  return select(value < 0 ? (null, -value) : (value, null))();
}

(Step, Read) counter(int start) {
  int advance(int n) => start += effects.tick(n);
  int read() => start;
  return (advance, read);
}

int sharedCounter(int n) {
  final (add, read) = counter(2);
  final (other, peek) = counter(5);
  try {
    add(3);
    other(1);
    add(n);
  } on Error {
    add(1);
  }
  return read() * 10 + peek();
}

Step Function(int) nested(int base) {
  Step make(int bias) =>
      (int n) => base += effects.tick(n) + bias;
  return make;
}

int transitive(int n) {
  final make = nested(2);
  final first = make(1), second = make(4);
  return first(n) * 10 + second(2);
}

int recursive(int n) {
  int fact(int k) => k < 2 ? 1 : k * fact(k - 1);
  final Step saved = fact;
  return saved(n);
}

int iteration(bool skip) {
  Read? first, last;
  for (var i = 0; i < 3; i++) {
    int getIndex() => ++i;
    if (i == 0) first = getIndex;
    last = getIndex;
    if (skip) continue;
    effects.tick(i);
  }
  return first!() * 100 + last!() * 10 + first();
}

int destructuredLoop(int limit) {
  Read? first, last;
  for (var (i, step) = (0, 1); i < limit; (i, step) = (i + step, step + 1)) {
    int read() => i * 10 + step;
    first ??= read;
    last = read;
  }
  return (first?.call() ?? 0) * 100 + (last?.call() ?? 0);
}

class Parent(var int value) {
  Step get callback {
    effects.tick(3);
    return effects.tick;
  }
}

class Owner(super.value) extends Parent {
  Step change(int bias) => (n) {
    value += effects.tick(n);
    return super.value + bias;
  };

  Step fromParent() =>
      (n) => super.callback(effects.tick(n));
}

int capturedReceiver(int n) {
  final owner = Owner(n);
  final f = owner.change(3);
  owner.value = 4;
  return f(2) + owner.value;
}

int capturedSuperGetter(int n) => Owner(2).fromParent()(n);

int scoped(int n) {
  var value = n;
  int read() => value;
  {
    final value = 6;
    int inner() => value;
    if (n < 0) return inner();
  }
  value = 7;
  return read();
}

class CaptureInField(int start) {
  // ignore: prefer_function_declarations_over_variables
  final Step step = (int n) => start + effects.tick(n);
}

class CaptureInInit(final Step step) {
  new counter(int start) : this((int n) => start += effects.tick(n));
}

int inConstructors(int n) {
  final a = CaptureInField(3), b = CaptureInInit.counter(3);
  final f = b.step;
  return a.step(n) * 100 + f(n) * 10 + f(1);
}

int updateBindings() {
  Read? first, update;
  for (var i = 0; i < 2; update = () => i, i++) {
    first ??= () => i;
  }
  return first!() * 10 + update!();
}

Read onExit(bool early) {
  var n = 2;
  try {
    if (early) return () => n;
    throw 7;
  } on int catch (e) {
    n += e;
    return () => n;
  } finally {
    n += effects.tick(3);
  }
}

int afterExit(bool early) => onExit(early)();

int inGuards(int n) {
  Read? saved;
  bool keep(Read read) {
    saved = read;
    return true;
  }

  switch (n) {
    case var x when x > 1 && keep(() => x):
    case var x when keep(() => x):
      x += 10;
      return saved!() * 100 + x;
    default:
      return -1;
  }
}
