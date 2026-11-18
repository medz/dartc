int constructed = 0;

abstract class Source<T> {
  factory(T value, {int z}) = Implementation<T>;
  factory own(T value, {int z = 17}) => Implementation<T>(value, z: z);
  T get value;
  int get z;
}

class Implementation<T>(
  @override final T value, {
  int extra = 7,
  @override final int z = 11,
}) implements Source<T> {
  this {
    constructed += extra;
  }
}

typedef Alias<X extends num> = Source<X>;

class Throwing(final int value) {
  this {
    constructed += 5;
    if (value < 0) throw value;
  }
}

int caught(int value) {
  constructed = 0;
  final make = Throwing.new;
  try {
    final instance = make(value);
    return instance.value + constructed;
  } on int catch (error) {
    return error - constructed;
  }
}

int factoryBody(int value) {
  constructed = 0;
  final make = Source<int>.own;
  final instance = make(value);
  return instance.value + instance.z + constructed;
}

int redirected(int value) {
  constructed = 0;
  final make = Source<int>.new;
  final instance = make(value);
  return instance.value + instance.z + constructed;
}

int named(int value) {
  constructed = 0;
  final make = Source<int>.new;
  final instance = make(value, z: 29);
  return instance.value + instance.z + constructed;
}

int generic(int value) {
  constructed = 0;
  final make = Source.new;
  final instance = make<int>(value);
  return instance.value + instance.z + constructed;
}

int alias(int value) {
  constructed = 0;
  final make = Alias.new;
  final instance = make<int>(value);
  return instance.value + instance.z + constructed;
}

int defaulted(
  int value, {
  Source<int> Function(int, {int z}) make = Source<int>.new,
}) {
  constructed = 0;
  final instance = make(value);
  return instance.value + instance.z + constructed;
}

int useDefault(int value) => defaulted(value);

int nested(int value) {
  constructed = 0;
  const functions = (Source<int>.new,);
  final instance = functions.$1(value);
  return instance.value + instance.z + constructed;
}

bool concreteIdentity() => identical(Source<int>.new, Source<int>.new);

bool instantiatedEquality() {
  final make = Source.new;
  return Source<int>.new == make<int>;
}

bool aliasIdentity() => identical(Alias.new, Source.new);

Object unusedTearOff() => Implementation.new;
