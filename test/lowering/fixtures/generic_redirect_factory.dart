// ignore_for_file: unnecessary_type_name_in_constructor, use_primary_constructors
import 'effects.dart' as effects;

abstract class Redirect<T> {
  factory Redirect(T value, {int? bonus}) = Middle<T, String>.named;
  factory Redirect.positional([T? value]) = Concrete<String, T>.positional;
  T? get value;
  int get score;
}

abstract class Middle<U, V> implements Redirect<U> {
  factory Middle.named(U value, {int? bonus}) = Concrete<V, U>.build;
}

class Concrete<X, W> implements Middle<W, X> {
  @override
  final W? value;
  @override
  final int score;
  Concrete(this.value, this.score);
  Concrete.positional([this.value, this.score = 9]);
  factory Concrete.build(W value, {int? bonus = 7, int extra = 3}) =>
      Concrete<X, W>(value, (bonus ?? 0) + extra);
}

abstract class NumberRedirect<T extends num> {
  factory NumberRedirect(T value) = NumberConcrete<T>;
  T get value;
}

class NumberConcrete<U extends num> implements NumberRedirect<U> {
  @override
  final U value;
  NumberConcrete(this.value);
}

int genericRedirect(int seed, int mode) {
  final Redirect<int> result = switch (mode) {
    0 => Redirect<int>(effects.tick(seed)),
    1 => Redirect<int>(effects.tick(seed), bonus: null),
    2 => Redirect<int>(bonus: effects.tick(2), effects.tick(seed)),
    3 => Redirect<int>.positional(),
    4 => Redirect<int>.positional(null),
    _ => Redirect<int>.positional(effects.tick(seed)),
  };
  return (result.value ?? 0) +
      result.score +
      (result is Concrete<String, int> ? 100 : 0) +
      (result is Concrete<String, String> ? 1000 : 0);
}

int genericRedirectTearoff(int seed, int mode) {
  final named = Redirect<int>.new;
  final positional = Redirect<int>.positional;
  final result = switch (mode) {
    0 => named(effects.tick(seed)),
    1 => named(effects.tick(seed), bonus: null),
    2 => named(bonus: effects.tick(2), effects.tick(seed)),
    3 => positional(),
    4 => positional(null),
    _ => positional(effects.tick(seed)),
  };
  return (result.value ?? 0) +
      result.score +
      (result is Concrete<String, int> ? 100 : 0);
}

int genericRedirectIdentity() {
  final first = Redirect<int>.new;
  final same = Redirect<int>.new;
  final different = Redirect<String>.new;
  final destination = Concrete<String, int>.build;
  final pos = Redirect<int>.positional;
  return (identical(first, same) ? 1 : 0) +
      (first == same ? 2 : 0) +
      (identical(first, different) ? 4 : 0) +
      (first == destination ? 8 : 0) +
      (first == pos ? 16 : 0);
}

int genericRedirectBounds(int seed) {
  final make = NumberRedirect<int>.new;
  final result = make(seed);
  return result.value + (result is NumberConcrete<int> ? 100 : 0);
}

class Holder<T> {
  final T value;
  Holder(this.value);
  Redirect<T> redirect() => Redirect<T>(value);
  Redirect<T> Function(T, {int? bonus}) tearoff() => Redirect<T>.new;
}

int genericRedirectEnvironment(int seed) {
  final holder = Holder<int>(seed);
  final a = holder.redirect();
  final b = holder.tearoff()(seed);
  return a.value! +
      b.value! +
      (a is Concrete<String, int> && b is Concrete<String, int> ? 100 : 0);
}
