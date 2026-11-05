// ignore_for_file: implicit_call_tearoffs, unnecessary_this, unnecessary_type_check, prefer_function_declarations_over_variables
import 'effects.dart';

extension type const Number(int value) {
  int plus(int other, [int extra = 2]) => value + other + extra;
  int named({int extra = 2, required int other}) => value + extra + other;
  int get doubled => value * 2;
  set observed(int input) {
    tick(value + input);
  }

  int operator +(int other) => value + other;
  int operator -() => -value;
  int operator [](int index) => value + index;
  void operator []=(int index, int input) {
    tick(value + index + input);
  }

  int call(int input) => value + input;
  int Function() capture() =>
      () => this.value;
  int lexical() => (() => plus(1))();
  T choose<T>(T input) => input;
  static Number get zero => Number(0);
  static Number from(int input) => Number(input);
  static int shared = 0;
  static int get current => shared;
  static set current(int input) {
    shared = input;
  }

  static int apply(int input) => input + shared;
}

extension type const Maybe(int? value) {
  int orZero() => value ?? 0;
  int Function() capture() =>
      () => value ?? 0;
}

extension type const Pair((int, int) value) {
  int sum() => value.$1 + value.$2;
}

extension type const Callable(int Function(int) value) {
  int apply(int input) => value(input);
  int Function(int) capture() =>
      (input) => value(input);
}

extension type Wrapped(Number value) {
  int read() => value.value;
}

int basic(int seed) {
  final n = Number(tick(seed));
  return n.named(other: tick(1)) +
      n.value +
      n.plus(tick(3)) +
      n.doubled +
      (n + 4) +
      -n +
      n[5];
}

int captures(int seed) {
  final n = Number(seed);
  final method = n.plus;
  final generic = n.choose;
  int Function(int) call = n;
  return call(6) +
      n.capture()() +
      n.lexical() +
      method(3) +
      generic<int>(4) +
      n(5);
}

int updates(int seed) {
  final n = Number(seed);
  n.observed = tick(2);
  n[tick(3)] += tick(4);
  return n.value;
}

int statics(int seed) {
  Number.current = seed;
  return Number.apply(2) + Number.current;
}

int nullable(int? seed) {
  final n = Maybe(seed);
  return n.orZero() + n.capture()();
}

int nullAware(bool absent) {
  Number? n = absent ? null : Number(3);
  return n?.plus(tick(4)) ?? 0;
}

int record(int seed) => Pair((seed, 4)).sum();
int functions(int seed) {
  final n = Callable((value) => value + seed);
  return n.apply(3) + n.capture()(4);
}

int nested(int seed) => Wrapped(Number(seed)).read();
int constructors(int seed) {
  final make = Number.new;
  final maybe = Maybe.new;
  final pair = Pair.new;
  final callable = Callable.new;
  return make(seed).value +
      maybe(null).orZero() +
      pair((seed, 1)).sum() +
      callable((v) => v + 2).apply(seed);
}

bool constructorIdentity() => identical(Number.new, Number.new);
int constants() {
  const n = Number(3);
  const m = Maybe(null);
  const p = Pair((4, 5));
  const make = Number.new;
  return n.value + m.orZero() + p.sum() + make(6).value;
}

bool checks(Object? value) => value is Number;
int casts(Object? value) => (value as Number).value;
typedef NullableInt = int?;
typedef IntPair = (int, int);
bool typeValues() => Number == int && Maybe == NullableInt && Pair == IntPair;
bool nestedTypes() => <Number>[Number(3)] is List<int>;
int patterns(Object? value) => switch (value) {
  Number(value: final v) => v,
  _ => -1,
};

bool identity(int seed) =>
    identical(Number(seed), seed) && identical(Maybe(null), null);
int cascades(int seed) {
  final n = Number(tick(seed))
    ..observed = tick(2)
    ..[tick(3)] = tick(4);
  return n.value;
}

int checkedConstruction(dynamic value) => Number(value).value;
int optionalNullAware(int? value) => Maybe(value)?.orZero() ?? -1;

extension type DynamicView(dynamic value) {
  int operator [](int index) => tick(index + 40);
  int plus(int input) => tick(input + 20);
}

int dynamicRepresentation(int seed) {
  final n = DynamicView(null)
    ..[tick(seed)]
    ..plus(tick(2));
  return n[tick(3)];
}

int shorthand(int seed) {
  Number a = .new(seed);
  Number b = .zero;
  Number c = .from(seed + 1);
  return a.value + b.value + c.value;
}

extension type const ListView(List<int> value) {
  int first() => value[0];
}

int increment(int value) => value + 1;
int moreConstants() {
  const list = ListView([4, 5]);
  const callable = Callable(increment);
  return list.first() + callable.apply(6);
}

T retain<T extends Number>(T value) => value;
int genericContext(int seed) => retain(Number(seed)).value;

typedef NumberAlias = Number;
bool aliasIdentity() {
  final make = NumberAlias.new;
  const constant = NumberAlias.new;
  return identical(make, Number.new) &&
      identical(constant, Number.new) &&
      make(3).value == 3;
}
