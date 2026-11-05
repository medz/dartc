// ignore_for_file: unnecessary_this, unnecessary_type_check, prefer_function_declarations_over_variables, implicit_call_tearoffs
import 'effects.dart';

extension type const Box<T>(T value) {
  T get() => value;
  T Function() capture() =>
      () => value;
  T Function() tearOff() => get;
  bool kind() => null is T;
  U choose<U extends T>(U input) => input;
  bool methodKind<U extends T>() => null is U;
  bool Function() captureType() =>
      () => null is T;
  bool recursive<U extends T>(Object? input, bool again) {
    if (!again) return input is U;
    final same = recursive;
    return same<U>(input, false);
  }
}

extension type const Phantom<T>(int value) {
  bool kind() => null is T;
  bool accepts(Object? input) => input is T;
  bool Function(Object?) capture() =>
      (input) => input is T;
  T cast(Object? input) => input as T;
}

extension type const Bounded<T extends num>(T value) {
  T get() => value;
  bool kind() => T == num;
  U choose<U extends T>(U input) => input;
}

extension type const Pair<A, B>((A, B) value) {
  A first() => value.$1;
  B second() => value.$2;
}

extension type const ListBox<T>(List<T> value) {
  T first() => value[0];
  bool kind() => null is T;
  bool methodKind<U extends T>() => null is U;
}

int direct(int seed) =>
    Box(seed).get() + Box<int>(seed).capture()() + Box<int>(seed).tearOff()();
int pair(int seed) =>
    Pair<int, int>((seed, 2)).first() + Pair<int, int>((seed, 2)).second();
int nullable(int? seed) =>
    (Box<int?>(seed).get() ?? 0) + (Box<int?>(seed).capture()() ?? 1);
bool phantom(Object? value) =>
    Phantom<int>(0).accepts(value) == Phantom<int>(0).capture()(value) &&
    Phantom<int?>(0).kind() &&
    !Phantom<int>(0).kind();
int phantomCast(Object? value) => Phantom<int>(0).cast(value);
int genericMethod(int seed) {
  final box = Box<num>(seed);
  final choose = box.choose;
  dynamic dynamicChoose = choose;
  return choose<int>(seed) +
      (dynamicChoose<int>(2) as int) +
      box.choose<int>(3);
}

bool dynamicMethodDefault() {
  dynamic function = Box<num>(1).methodKind;
  return function();
}

bool dynamicListDefault() {
  dynamic function = ListBox<num>([1]).methodKind;
  return function();
}

bool recursive() => Box<num>(1).recursive<int>(1.5, true);
T Function() escape<T>(T value) => Box<T>(value).get;
int escaped(int seed) => escape<int>(seed)();
int throughBound<B extends Box<int>>(B box) => (box as Box<int>).get();
int boundedReceiver(int seed) => throughBound(Box(seed));
int constructors(int seed) {
  final generic = Box.new;
  final explicit = Box<int>.new;
  Box<int> Function(int) inferred = Box.new;
  return generic<int>(seed).value + explicit(seed).value + inferred(seed).value;
}

bool constructorIdentity() {
  final generic = Box.new;
  return identical(generic, Box.new) &&
      identical(generic<int>, Box<int>.new) &&
      !identical(Phantom<int>.new, Phantom<String>.new);
}

int dynamicConstructor(int seed) {
  dynamic generic = Bounded.new;
  return (generic<int>(seed) as Bounded<int>).get();
}

int dynamicArgument(dynamic value) {
  try {
    return Box<int>(value).get();
  } finally {
    tick(5);
  }
}

Object? dynamicBound(bool valid) {
  dynamic generic = Bounded.new;
  return valid ? generic<num>(3) : generic<String>('bad');
}

bool constIdentity() =>
    identical(const Phantom<int>(1), const Phantom<String>(1));
int constants() {
  const box = Box<int>(3);
  const pair = Pair<int, int>((4, 5));
  const list = ListBox<int>([6]);
  const generic = Box.new;
  const explicit = Box<int>.new;
  return box.value +
      pair.first() +
      list.first() +
      generic<int>(7).value +
      explicit(8).value;
}

bool typeChecks(Object? value) => value is Box<int>;
bool erasedPhantomType() =>
    (Phantom<int>) == (Phantom<String>) && (Box<int>) == int;
bool genericReification<T>() => T == int;
bool reification() => genericReification<Box<int>>();
int pattern(Object? value) => switch (value) {
  Box<int>(value: final v) => v,
  _ => -1,
};

extension type const MaybeBox<T>(T? value) {
  bool isAbsent() => value == null;
  bool kind() => null is T;
}

extension type FunctionBox<T>(T Function() value) {
  T apply() => value();
}

int shorthand(int seed) {
  Box<int> box = .new(seed);
  Box<int> Function(int) make = Box<int>.new;
  return box.value + make(seed).value;
}

bool phantomInference() {
  Phantom<int> Function(int) make = Phantom.new;
  return make(1).accepts(2) && !make(1).accepts('bad');
}

Phantom<T> Function(int) escapeConstructor<T>() => Phantom<T>.new;
bool escapedConstructor() => escapeConstructor<String>()(1).accepts('yes');
bool nullableRepresentation() =>
    MaybeBox<int>(null).isAbsent() &&
    !MaybeBox<int>(null).kind() &&
    MaybeBox<int?>(null).kind();
int functionRepresentation(int seed) =>
    FunctionBox<int>(() => seed + 2).apply();
bool widenedView() {
  final narrow = Phantom<int>(3);
  final wide = narrow as Phantom<Object?>;
  return !narrow.accepts('str') &&
      wide.accepts('str') &&
      identical(narrow, wide);
}

bool rawConstructorIdentity() => identical(Box.new, Box.new);
bool instantiatedConstructorIdentity() {
  final make = Box.new;
  return identical(make<int>, Box<int>.new);
}

bool phantomConstructorIdentity() =>
    identical(Phantom<int>.new, Phantom<String>.new);
bool appliedConstructorIdentity() => identical(Box<int>.new, Box<int>.new);
bool methodIdentity() {
  final value = Phantom<int>(3);
  final first = value.accepts;
  final second = value.accepts;
  return identical(first, second);
}

bool patternPhantom() {
  bool Function(Object?)? previous;
  bool remember(bool Function(Object?) function) {
    previous = function;
    return false;
  }

  return switch (1) {
    Phantom<int>(accepts: final function) when remember(function) => false,
    Phantom<String>(accepts: final function) =>
      !previous!('x') && function('x'),
  };
}

typedef BottomCallback = void Function(Never);

extension type Defaults<T>(int value) {
  Type independent<U extends num>() => U;
  Type dependent<U extends T>() => U;
  Type covariant<U extends List<T>>() => U;
  Type contravariant<U extends void Function(T)>() => U;
  Type recursive<U extends Comparable<U>>() => U;
  Type recursiveContra<U extends void Function(U)>() => U;
  Type pair<U extends T, V extends U>() => V;
}

extension type BoundedDefaults<T extends num>(int value) {
  Type dependent<U extends T>() => U;
  Type contravariant<U extends void Function(T)>() => U;
}

bool defaultIndependent() {
  dynamic f = Defaults<int>(0).independent;
  return f() == num;
}

bool defaultDependent() {
  dynamic f = Defaults<int>(0).dependent;
  return f() == dynamic;
}

bool defaultCovariant() {
  dynamic f = Defaults<int>(0).covariant;
  return f() == List<dynamic>;
}

bool defaultContravariant() {
  dynamic f = Defaults<int>(0).contravariant;
  return f() == BottomCallback;
}

bool defaultRecursive() {
  dynamic f = Defaults<int>(0).recursive;
  return f() == Comparable<dynamic>;
}

bool defaultRecursiveContra() {
  dynamic f = Defaults<int>(0).recursiveContra;
  return f() == BottomCallback;
}

bool defaultPair() {
  dynamic f = Defaults<int>(0).pair;
  return f() == dynamic;
}

bool defaultBounded() {
  dynamic f = BoundedDefaults<int>(0).dependent;
  return f() == num;
}

bool defaultBoundedSuccess() {
  dynamic f = BoundedDefaults<num>(0).dependent;
  return f() == num;
}

bool defaultBoundedContra() {
  dynamic f = BoundedDefaults<int>(0).contravariant;
  return f() == BottomCallback;
}

Object? neverConstructor() {
  dynamic make = Box<Never>.new;
  return make(3);
}

bool constructorEquality() {
  final make = Box.new;
  return make<int> == Box<int>.new;
}

bool constPhantomConstructors() {
  const generic = Phantom.new;
  const string = Phantom<String>.new;
  return generic<int>(1).accepts(2) &&
      string(1).accepts('x') &&
      !identical(string, Phantom<int>.new);
}

extension type Operations<T>(int value) {
  bool operator [](Object? input) => input is T;
  void operator []=(int index, T input) {
    tick(index);
  }

  bool operator +(Object? input) => input is T;
  bool operator -() => null is T;
  T call(T input) => input;
  set checked(T input) {
    tick(value);
  }

  T Function(T) get function =>
      (input) => input;
}

bool operators(int seed) {
  final n = Operations<int>(seed);
  n[tick(1)] = tick(2);
  n.checked = tick(3);
  int Function(int) call = n;
  return n[seed] && !(n + 'bad') && !(-n) && call(4) == 4 && n.function(5) == 5;
}

int operatorChecks(dynamic value) {
  final n = Operations<int>(3);
  n[tick(1)] = value;
  return 0;
}

bool nullAware(int? seed) {
  final function = seed == null ? null : Box<int>(seed).get;
  return function?.call() == seed;
}

extension type RecursiveBound<T extends Comparable<T>>(int value) {
  bool kind() => T == Comparable<dynamic>;
}

extension type DependentBounds<A extends num, B extends A>((A, B) value) {
  A first() => value.$1;
  B second() => value.$2;
}

bool recursiveConstructorDefault() {
  dynamic make = RecursiveBound.new;
  return make(1) == 1;
}

num dependentConstructor(int seed) =>
    DependentBounds<num, int>((1.5, seed)).first() +
    DependentBounds<num, int>((1.5, seed)).second();

typedef IntBox = Box<int>;
bool genericOwnerAliasIdentity() {
  final make = IntBox.new;
  const constant = IntBox.new;
  return identical(make, Box<int>.new) &&
      identical(constant, Box<int>.new) &&
      make(2).value == 2;
}
