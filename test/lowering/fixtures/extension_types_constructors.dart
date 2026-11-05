// Closure expressions and explicit this intentionally exercise receiver capture.
// ignore_for_file: prefer_function_declarations_over_variables, unnecessary_this

import 'effects.dart';

extension type Primary(int value) {
  this : assert(probe(value)) {
    tick(value + 10);
    final read = () => this.value;
    tick(read() + 20);
  }
  new other(int x, [int add = 2]) : value = tick(x + add) {
    try {
      tick(value + 30);
      if (x == 0) return;
      tick(value + 40);
    } finally {
      tick(value + 50);
    }
  }
  new redirect(int x, {int add = 3}) : this.other(tick(x), add);
  factory make(int x, {int add = 4}) {
    tick(x);
    return Primary.other(x, add);
  }
}

extension type Generic<T>(T value) {
  this {
    final read = () => value;
    saved = read;
  }
  new named(T x) : value = x {
    final read = () => value;
    saved = read;
  }
}

Object? Function()? saved;
int primary(int x) => Primary(tick(x)).value;
int other(int x) => Primary.other(tick(x)).value;
int redirect(int x) => Primary.redirect(tick(x)).value;
int factory(int x) => Primary.make(tick(x)).value;
Object? generic(int x) {
  Generic<int>.named(x);
  return saved!();
}

Object? genericPrimary(int x) {
  Generic<int>(x);
  return saved!();
}

int tearoff(int x) {
  final f = Primary.other;
  return f(x).value;
}

int factoryTearoff(int x) {
  final f = Primary.make;
  return f(x).value;
}

extension type Nullable<T>(T? value) {
  new named([T? x]) : value = x;
  new redirect([T? x]) : this.named(x);
  factory make([T? x]) => Nullable<T>.redirect(x);
}

extension type ConstBox<T>(T value) {
  const new named(this.value);
  const new redirect(T x) : this.named(x);
  const new checked(T x, bool valid) : assert(valid), value = x;
}

extension type Ordered(int value) {
  new named(int x)
    : assert(probe(x + 1), tick(70)),
      value = tick(x + 2),
      assert(probe(x + 3), tick(80)) {
    try {
      tick(x + 4);
      final f = () => value;
      saved = f;
      if (x == 1) throw 'body';
    } finally {
      tick(x + 5);
    }
  }
}

int ordered(int x) => Ordered.named(x).value;
Object? nullable(int x) {
  final make = Nullable<int>.make;
  return '${make().value}:${make(x).value}:${Nullable<int>.redirect().value}';
}

Object? genericConstructor(int x) {
  final f = Nullable.named;
  return '${f<int>(x).value}:${f<String>('ok').value}';
}

Object? constConstructors() {
  const a = ConstBox<int>.redirect(4);
  const b = ConstBox<int>.named(4);
  const f = ConstBox<int>.named;
  return '${a.value}:${identical(a, b)}:${f(5).value}:${identical(f, ConstBox<int>.named)}';
}

int runtimeConst(int x) => ConstBox<int>.checked(x, x > 0).value;
Object? capturedAfterReturn(int x) {
  Primary.other(x);
  return Generic<int>.named(x).value;
}

Object? nullableDynamic(Object? x) {
  dynamic f = Nullable<int>.named;
  return (f(x) as Nullable<int>).value;
}

extension type RecursiveDefaults(int value) {
  new self([Object? f = RecursiveDefaults.self])
    : value = identical(f, RecursiveDefaults.self) ? 1 : 0;
  new left([Object? f = RecursiveDefaults.right])
    : value = identical(f, RecursiveDefaults.right) ? 2 : 0;
  new right([Object? f = RecursiveDefaults.left])
    : value = identical(f, RecursiveDefaults.left) ? 3 : 0;
}

int recursiveDefaults() =>
    RecursiveDefaults.self().value +
    RecursiveDefaults.left().value +
    RecursiveDefaults.right().value;

extension StaticDefaults on int {
  static bool self([Object? f = StaticDefaults.self]) =>
      identical(f, StaticDefaults.self);
  static bool left([Object? f = StaticDefaults.right]) =>
      identical(f, StaticDefaults.right);
  static bool right([Object? f = StaticDefaults.left]) =>
      identical(f, StaticDefaults.left);
}

bool staticDefaults() =>
    StaticDefaults.self() && StaticDefaults.left() && StaticDefaults.right();
