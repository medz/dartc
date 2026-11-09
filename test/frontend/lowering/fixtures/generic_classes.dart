// ignore_for_file: type_check_with_null, unnecessary_type_check, unnecessary_type_name_in_constructor, use_primary_constructors, use_super_parameters
import 'effects.dart';

class Box<T> {
  T value;
  Box(this.value);
  Box.named(T value) : this(value);
  factory Box.make(T value) => Box<T>(value);
  T get current => value;
  set current(T next) {
    value = next;
  }

  T replace(T next) {
    final old = value;
    value = next;
    return old;
  }

  bool matches(Object? candidate) => candidate is T;
  T cast(Object? candidate) => candidate as T;
  Object requireValue() => value!;
  (T, bool) pair() => (value, value is T);
  bool Function(Object?) checker() =>
      (Object? candidate) => candidate is T;
  T Function(T) identity() =>
      (T value) => value;
}

class Child<U> extends Box<U> {
  Child(U value) : super(value);
  U parentReplace(U next) => super.replace(next);
}

class IntBox extends Child<int> {
  IntBox(int value) : super(value);
}

class Bounded<T extends num> {
  final T value;
  Bounded(this.value);
  num add(int amount) => value + amount;
}

int genericStorage(int seed) {
  final ints = Box<int>(tick(seed));
  final strings = Box<String>('text');
  ints.current = tick(seed + 1);
  return ints.replace(tick(seed + 2)) +
      ints.current +
      (strings.current == 'text' ? 10 : 0);
}

bool genericTypes(Object? candidate) {
  return Box<int>(1).matches(candidate);
}

bool genericNullableTypes(Object? candidate) {
  return Box<int?>(null).matches(candidate);
}

Object? genericCast(Object? candidate) => Box<int>(1).cast(candidate);

bool genericClosure(Object? candidate) {
  final checkInt = Box<int>(1).checker();
  final checkString = Box<String>('x').checker();
  return checkInt(candidate) && !checkString(candidate);
}

int genericInheritance(int seed) {
  final value = IntBox(seed);
  return value.parentReplace(seed + 1) + value.current;
}

bool genericSubtype(int seed) {
  final Object value = IntBox(seed);
  return value is Box<int> && value is Child<num> && value is! Box<String>;
}

int genericFactories(int seed) {
  return Box<int>.named(seed).value + Box<int>.make(seed + 1).value;
}

num genericBound(int seed) => Bounded<int>(seed).add(2);

int genericCovariantWrite(int seed) {
  final Box<num> box = Box<int>(seed);
  try {
    box.current = 2.5;
  } on TypeError {
    return box.value as int;
  }
  return -100;
}

int genericCovariantCall(int seed) {
  final Box<num> box = Box<int>(seed);
  try {
    box.replace(2.5);
  } on TypeError {
    return box.value as int;
  }
  return -100;
}

bool genericTearoff(int seed) {
  final box = Box<int>(seed);
  final Object replace = box.replace;
  final Object identity = box.identity();
  return replace is int Function(Object?) &&
      identity is int Function(int) &&
      identity is! int Function(Object?);
}

int genericTearoffCall(int seed) {
  final Box<num> box = Box<int>(seed);
  final replace = box.replace;
  try {
    replace(2.5);
  } on TypeError {
    return box.value as int;
  }
  return -100;
}

int genericConstructorTearoff(int seed) {
  final create = Box<int>.new;
  final make = Box<int>.make;
  return create(seed).value + make(seed + 1).value;
}

bool genericConstructorIdentity() {
  return Box<int>.new == Box<int>.new && Box<int>.new != Box<String>.new;
}

bool genericNestedType(Object? candidate) {
  final box = Box<Box<int>>(Box<int>(1));
  return box.matches(Box<int>(2)) &&
      !box.matches(Box<String>('x')) &&
      box.value.matches(candidate);
}

class Pair<A, B> extends Box<B> {
  final A first;
  Pair(this.first, B second) : super(second);
  bool firstMatches(Object? candidate) => candidate is A;
}

int genericReorderedInheritance(int seed) {
  final pair = Pair<String, int>('first', seed);
  return pair.current + (pair.firstMatches('second') ? 10 : 0);
}

class Variance<T> {
  void consume(T value) {}
  void callback(void Function(T) value) {}
  void producer(T Function() value) {}
}

bool genericVariance() {
  final value = Variance<int>();
  final Object consume = value.consume;
  final Object callback = value.callback;
  final Object producer = value.producer;
  return consume is void Function(Object?) &&
      callback is void Function(void Function(int)) &&
      callback is! void Function(Object?) &&
      producer is void Function(Object?);
}

Object genericNonNull(Object? candidate) =>
    Box<Object?>(candidate).requireValue();

int genericRecord(int seed) {
  final (value, matches) = Box<int>(seed).pair();
  return value + (matches ? 1 : 0);
}

class Recursive<T extends Recursive<T>> {
  bool matches(Object candidate) => candidate is T;
}

class RecursiveLeaf extends Recursive<RecursiveLeaf> {}

class Base<T> {
  bool matches(Object candidate) => candidate is T;
}

class Self<T> extends Base<Self<T>> {}

class Wrap<T extends Box<int>> {
  final T value;
  Wrap(this.value);
  int read() => value.current;
}

class NullableBox<T> {
  final T value;
  NullableBox(this.value);
  T fallback(T fallback) => value ?? fallback;
  int nullBranch() => value == null ? 1 : 2;
  int nullTest() => value is Null ? 10 : 20;
  Object nonNullBranch() {
    final local = value;
    if (local == null) return 'missing';
    return local;
  }
}

bool genericRecursiveBound() {
  final value = RecursiveLeaf();
  return value.matches(RecursiveLeaf()) && !value.matches(Box<int>(1));
}

bool genericSelfHierarchy() {
  final value = Self<int>();
  return value.matches(Self<int>()) && !value.matches(Self<String>());
}

int genericBoundReceiver(int seed) => Wrap<IntBox>(IntBox(seed)).read();

Object? genericNullOperations(Object? value) {
  final box = NullableBox<Object?>(value);
  final fallback = box.fallback('fallback');
  return '${box.nullBranch()}:${box.nullTest()}:${box.nonNullBranch()}:$fallback';
}

const intBoxConstructor = Box<int>.new;
int genericConstantTearoff(int seed) => intBoxConstructor(seed).value;
int _withDefaultTearoff(
  int seed, [
  Box<int> Function(int) create = Box<int>.new,
]) => create(seed).value;

int genericDefaultTearoff(int seed) => _withDefaultTearoff(seed);
