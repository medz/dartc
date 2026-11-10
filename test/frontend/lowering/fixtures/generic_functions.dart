// Runtime checks intentionally include positive and negative type tests.
// ignore_for_file: unnecessary_type_check, dead_code, use_primary_constructors, unnecessary_type_name_in_constructor, implicit_call_tearoffs, prefer_function_declarations_over_variables
import 'effects.dart';

T identity<T>(T value) => value;
T bounded<T extends num>(T value) => value;

int genericDirect(int seed) => identity<int>(tick(seed)) + identity(seed + 1);
int genericBounded(int seed) => bounded<int>(seed);

bool changesType<T>(int depth, Object value) {
  if (depth == 0) return value is T;
  return changesType<String>(depth - 1, value);
}

bool genericRecursion(int depth) => changesType<int>(depth, 'yes');

int genericFunctionValue(int seed) {
  final T Function<T>(T) function = identity;
  return function<int>(seed) + function(seed + 1);
}

int genericInstantiation(int seed) {
  final explicit = identity<int>;
  final int Function(int) implicit = identity;
  return explicit(seed) + implicit(seed + 1);
}

bool genericFunctionTests() {
  final Object value = identity;
  return value is T Function<T>(T) &&
      value is U Function<U>(U) &&
      value is! int Function(int) &&
      value is! T Function<T extends num>(T);
}

bool genericInstantiationTests() {
  final Object value = identity<int>;
  return value is int Function(int) &&
      value is num Function(int) &&
      value is! String Function(String) &&
      value is! T Function<T>(T);
}

bool genericTearoffEquality() =>
    (identity<int>) == (identity<int>) && (identity<int>) != (identity<String>);

class GenericHost<T> {
  final T stored;
  GenericHost(this.stored);
  static GenericHost<U> create<U>(U value) => GenericHost<U>(value);
  U choose<U>(T first, U second) {
    tick(101);
    return first is T ? second : throw StateError('owner type lost');
  }

  U constrained<U extends T>(U value) => value;

  bool Function<V>(Object, Object, Object) captureBoth<U>() {
    bool local<V>(Object owner, Object method, Object local) =>
        owner is T && method is U && local is V;
    return local;
  }

  bool Function<U>(Object, Object) capture() {
    bool check<U>(Object outer, Object inner) => outer is T && inner is U;
    return check;
  }
}

class GenericChild<T> extends GenericHost<T> {
  GenericChild(super.stored);
  @override
  U choose<U>(T first, U second) {
    tick(102);
    return super.choose<U>(first, second);
  }
}

int genericMethod(int seed) => GenericHost<String>('x').choose<int>('y', seed);
int genericVirtualMethod(int seed) {
  final GenericHost<String> host = GenericChild<String>('x');
  return host.choose<int>('y', seed);
}

int genericMethodTearoff(int seed) {
  final GenericHost<String> host = GenericChild<String>('x');
  final function = host.choose;
  final instantiated = function<int>;
  return function<int>('y', seed) + instantiated('z', seed + 1);
}

bool genericCapturedOwner(Object candidate) {
  final function = GenericHost<String>('x').capture();
  return function<int>('x', candidate);
}

bool capturesFunction<T>(T outer, Object candidate) {
  bool local<U>(U inner) => outer is T && inner is U && candidate is T;
  return local<int>(1);
}

bool genericCapturedFunction(Object candidate) =>
    capturesFunction<String>('x', candidate);

int genericLocalRecursion(int seed) {
  int local<T>(int depth) {
    if (depth == 0) return seed + (1 is T ? 10 : 20);
    return local<String>(depth - 1);
  }

  final specialized = local<int>;
  return specialized(2);
}

int genericCovariantMethod(int seed) {
  final GenericHost<num> host = GenericHost<int>(seed);
  try {
    return host.choose<int>(2.5, seed);
  } on TypeError {
    return -100;
  }
}

bool genericDependentBound<T, U extends T>(T first, U second) => second is T;
bool genericDependentBounds() => genericDependentBound<num, int>(1.5, 2);

int genericRuntimeBound(int seed) {
  final GenericHost<num> host = GenericHost<int>(seed);
  try {
    host.constrained<double>(2.5);
    return 0;
  } on TypeError {
    return -100;
  }
}

bool genericLocalEquality() {
  T local<T>(T value) => value;
  return (local<int>) == (local<int>) && (local<int>) != (local<String>);
}

int genericConstructorFunction(int seed) {
  final constructor = GenericHost.new;
  final GenericHost<int> Function(int) specialized = constructor;
  return constructor<int>(seed).stored + specialized(seed + 1).stored;
}

int genericOptionalNamed(int seed) {
  T choose<T>(T first, {T? second}) => second ?? first;
  final function = choose;
  return function<int>(seed, second: seed + 1) + function<int>(seed);
}

int unusedTypeParameter<T>() => 1;
bool genericUnusedTypeIdentity() =>
    (unusedTypeParameter<int>) != (unusedTypeParameter<String>);

class GenericCallable {
  T call<T>(T value) => value;
}

int genericCallable(int seed) {
  final callable = GenericCallable();
  final T Function<T>(T) function = callable;
  return callable<int>(seed) +
      function<int>(seed + 1) +
      callable.call<int>(seed + 2);
}

T Function<T>(T) get genericGetter => identity;
int genericGetterCall(int seed) => genericGetter<int>(seed);
int genericExplicitCall(int seed) {
  final function = identity;
  return function.call<int>(seed);
}

int genericNullableMethod(int seed) {
  final GenericHost<String>? host = seed == 0 ? null : GenericHost<String>('x');
  return host?.choose<int>('y', seed) ?? -100;
}

int genericCascadeMethod(int seed) {
  final host = GenericHost<String>('x')..choose<int>('y', tick(seed));
  return host.choose<int>('z', seed + 1);
}

class GenericStatics {
  static T relay<T>(T value) => value;
}

int genericStaticMethod(int seed) {
  final function = GenericStatics.relay;
  return GenericStatics.relay<int>(seed) + function<int>(seed + 1);
}

typedef GenericAlias<T> = GenericHost<T>;
int genericAliasConstructor(int seed) {
  final constructor = GenericAlias.new;
  return constructor<int>(seed).stored;
}

GenericHost<T> Function(T) lexicalConstructor<T>() => GenericHost<T>.new;

class ConstructorValues<T>() {
  final field = GenericHost<T>.new;
  late final lazy = GenericHost<T>.new;
  GenericHost<T> Function(T) get getter => GenericHost<T>.new;
  GenericHost<T> Function(T) method() => GenericHost<T>.new;
}

int genericLexicalConstructorChecks(int seed) {
  final ConstructorValues<num> wide = ConstructorValues<int>();
  var checks = 0;
  for (var kind = 0; kind < 4; kind++) {
    try {
      final make = switch (kind) {
        0 => wide.field,
        1 => wide.lazy,
        2 => wide.getter,
        _ => wide.method(),
      };
      tick(301);
      make(seed);
    } on TypeError {
      checks += 10;
    }
  }
  return lexicalConstructor<int>()(seed).stored + checks;
}

class GenericFactory<T> {
  final T stored;
  GenericFactory._(this.stored);
  factory GenericFactory(T value) = GenericFactory<T>._;
}

int genericFactoryConstructor(int seed) {
  final constructor = GenericFactory.new;
  final specialized = constructor<int>;
  return constructor<int>(seed).stored + specialized(seed + 1).stored;
}

int genericDotStaticMethod(int seed) {
  final GenericHost<int> host = .create<int>(seed);
  return host.stored;
}

bool genericCapturedBoth(Object candidate) {
  final function = GenericHost<String>('x').captureBoth<int>();
  return function<bool>('x', 1, candidate);
}

bool genericRawConstructorEquality() {
  final constructor = GenericHost.new;
  return (constructor<int>) == GenericHost<int>.new &&
      (constructor<int>) != GenericHost<String>.new;
}

class GenericPair<A, B> {
  final A first;
  final B second;
  GenericPair(this.first, this.second);
}

typedef FlippedPair<A, B> = GenericPair<B, A>;
typedef OtherFlippedPair<A, B> = GenericPair<B, A>;
typedef PhantomPair<A, B> = GenericPair<A, A>;
typedef FixedPair<A> = GenericPair<int, A>;
typedef RepeatedPair<A> = GenericPair<A, A>;
typedef RenamedPair<A, B> = GenericPair<A, B>;
typedef TightHost<T extends num> = GenericHost<T>;

int genericReorderedAliasConstructor(int seed) {
  final constructor = FlippedPair.new;
  final value = constructor<int, String>('x', seed);
  return value.second + (value.first == 'x' ? 10 : 0);
}

int genericFixedAliasConstructor(int seed) {
  final constructor = FixedPair.new;
  final value = constructor<String>(seed, 'x');
  return value.first + (value.second == 'x' ? 10 : 0);
}

int genericRepeatedAliasConstructor(int seed) {
  final constructor = RepeatedPair.new;
  final value = constructor<int>(seed, seed + 1);
  return value.first + value.second;
}

bool genericAliasConstructorEquality() {
  final flipped = FlippedPair.new;
  final fixed = FixedPair.new;
  final repeated = RepeatedPair.new;
  final renamed = RenamedPair.new;
  final phantom = PhantomPair.new;
  final tight = TightHost.new;
  return TightHost.new != GenericHost.new &&
      (tight<int>) != GenericHost<int>.new &&
      FlippedPair.new != OtherFlippedPair.new &&
      (phantom<int, String>) != (phantom<int, bool>) &&
      (flipped<int, String>) != GenericPair<String, int>.new &&
      (flipped<int, String>) != FlippedPair<int, String>.new &&
      (flipped<int, String>) == (flipped<int, String>) &&
      (fixed<String>) != GenericPair<int, String>.new &&
      (repeated<int>) != GenericPair<int, int>.new &&
      (renamed<int, String>) == GenericPair<int, String>.new &&
      RenamedPair.new == GenericPair.new &&
      FlippedPair<int, String>.new == GenericPair<String, int>.new;
}

bool genericAliasConstructorIdentity() {
  final constructor = FlippedPair.new;
  return identical(FlippedPair.new, FlippedPair.new) &&
      !identical(constructor<int, String>, constructor<int, String>);
}

int genericBoundTearoffExtraction(int seed) {
  final GenericHost<num> host = seed == 0
      ? GenericHost<num>(seed)
      : GenericHost<int>(seed);
  try {
    tick(201);
    final Object function = host.constrained;
    tick(202);
    return function is Function ? 1 : 0;
  } on TypeError {
    tick(203);
    return -100;
  } finally {
    tick(204);
  }
}

int consumeGenericTearoff(Object function, int next) => next;

int genericBoundTearoffEvaluationOrder(int seed) {
  final GenericHost<num> host = seed == 0
      ? GenericHost<num>(seed)
      : GenericHost<int>(seed);
  try {
    return consumeGenericTearoff(host.constrained, tick(211));
  } on TypeError {
    tick(212);
    return -100;
  } finally {
    tick(213);
  }
}

int genericBoundInstantiatedTearoff(int seed) {
  final GenericHost<num> host = seed == 0
      ? GenericHost<num>(seed)
      : GenericHost<int>(seed);
  try {
    final function = host.constrained<int>;
    tick(221);
    return function(seed);
  } on TypeError {
    tick(222);
    return -100;
  } finally {
    tick(223);
  }
}

class GenericCallbackBounds<T> {
  void takes(void Function<U extends T>(U) callback) {}
  void returns(U Function<U extends T>(U) Function() callback) {}
  void nested(void Function(void Function<U extends T>(U)) callback) {}
}

bool genericNestedBoundCovariance() {
  final GenericCallbackBounds<num> host = GenericCallbackBounds<int>();
  final Object takes = host.takes;
  final Object returns = host.returns;
  final Object nested = host.nested;
  return takes is void Function(Object?) &&
      returns is void Function(Object?) &&
      nested is void Function(Object?) &&
      takes is void Function(void Function<U extends int>(U)) &&
      returns is void Function(U Function<U extends int>(U) Function()) &&
      nested is void Function(void Function(void Function<U extends int>(U)));
}

int genericAnonymous(int seed) {
  final function = <T>(T value) => value;
  final specialized = function<int>;
  return function<int>(seed) + specialized(seed + 1);
}

bool genericNestedAnonymous(Object candidate) {
  final factory = <T>(T outer) =>
      <U>(U inner) => outer is T && inner is U && candidate is T;
  final function = factory<String>('x');
  return function<int>(1);
}

bool Function<U>(U) anonymousCaptures<T>(T outer, Object candidate) =>
    <U>(U inner) => outer is T && inner is U && candidate is T;

bool genericReturnedAnonymous(Object candidate) =>
    anonymousCaptures<String>('x', candidate)<int>(1);

bool acceptsNullLiteral<T>() => null is T;
bool rejectsNullLiteral<T>() => null is! T;
T castNullLiteral<T>() => null as T;

bool genericNullLiteralChecks() =>
    acceptsNullLiteral<int?>() &&
    !acceptsNullLiteral<int>() &&
    acceptsNullLiteral<Object?>() &&
    !acceptsNullLiteral<Object>() &&
    rejectsNullLiteral<int>() &&
    !rejectsNullLiteral<int?>() &&
    castNullLiteral<int?>() == null;

int genericNullLiteralCastFailure() {
  try {
    castNullLiteral<int>();
    return 0;
  } on TypeError {
    return 1;
  }
}
