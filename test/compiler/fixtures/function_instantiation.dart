import 'dart:ffi';

import 'package:dartc/interop.dart';

import 'closures.dart' show collect;

typedef Identity = T Function<T>(T);
typedef RenamedIdentity = U Function<U>(U);
T identity<T>(T value) => value;
T Function(T) identityFor<T>() => identity<T>;
int phantom<T>([int value = 7]) => value;

int useIdentity(Identity generic, int count) {
  final explicit = generic<int>;
  final int Function(int) inferred = generic;
  final number = generic<num>;
  collect(count);
  return explicit(2) * 10000 +
      inferred(3) * 1000 +
      number(4).toInt() * 100 +
      (explicit == (identity<int>) ? 10 : 0) +
      (explicit == inferred &&
              explicit != number &&
              explicit == identityFor<int>()
          ? 1
          : 0);
}

int usePhantom(int Function<T>() generic) =>
    (generic<int> == (generic<int>) ? 1 : 0) +
    (generic<int> != (generic<num>) ? 10 : 0) +
    (generic<int> == (phantom<int>) ? 100 : 0) +
    (generic<int>)() * 1000;

@Export<Int64 Function(Int64)>()
int staticFunctions(int count) =>
    useIdentity(identity, count) * 1000 + usePhantom(phantom);

int Function<T>(int) counter(int value) {
  int next<T>(int n) => value += n;
  return next;
}

int Function(int) specialize<T>(int Function<U>(int) generic) => generic<T>;

@Export<Int64 Function(Int64)>()
int closures(int count) {
  final generic = counter(1), other = counter(1);
  final first = generic<int>, second = generic<num>;
  final lexical = specialize<int>(generic);
  collect(count);
  return (first == lexical ? 1000000 : 0) +
      first(2) * 100000 +
      second(3) * 10000 +
      (first == (generic<int>) ? 1000 : 0) +
      (first != second ? 100 : 0) +
      (first != (other<int>) ? 10 : 0) +
      first(1);
}

class Box<T>(final T value) {
  U choose<U>(T first, U second) => second;
  U limited<U extends num>(U value) => value;
  T Function(T, T) bind() => choose<T>;
}

typedef PhantomBox<T, S> = Box<T>;
const phantomBox = PhantomBox.new;

int useConstructor(Box<T> Function<T>(T) make) {
  final applied = make<int>;
  return applied(4).value * 100 +
      (applied == Box<int>.new ? 10 : 0) +
      (applied == (make<int>) ? 1 : 0);
}

int useAlias(Box<T> Function<T, S>(T) make) =>
    (make<int, String> == (make<int, String>) ? 1 : 0) +
    (make<int, String> != (make<int, bool>) ? 10 : 0) +
    (make<int, String> != Box<int>.new ? 100 : 0) +
    (make<int, String> == (phantomBox<int, String>) ? 1000 : 0);

@Export<Int64 Function(Int64)>()
int constructors(int count) {
  collect(count);
  return useConstructor(Box.new) * 1000 + useAlias(PhantomBox.new);
}

@Export<Int64 Function(Int64)>()
int methods(int count) {
  final box = Box<int>(2), other = Box<int>(2);
  final generic = box.choose;
  final first = generic<int>, second = generic<num>;
  final bounded = box.limited<double>;
  final fromOwner = box.bind();
  collect(count);
  var checked = 0;
  try {
    (first as int Function(Object?, int))(1.5, 2);
  } on TypeError {
    checked = 1;
  }
  final Object actual = first;
  return checked * 10000000 +
      (first == fromOwner ? 1000000 : 0) +
      first(1, 2) * 100000 +
      second(1, 3).toInt() * 10000 +
      bounded(4.5).toInt() * 1000 +
      (first == (box.choose<int>) ? 100 : 0) +
      (first != (other.choose<int>) ? 10 : 0) +
      (actual is int Function(Object?, int) ? 1 : 0);
}

bool sameFunction(Object first, Object second) =>
    first == second && first.hashCode == second.hashCode;

@Export<Int64 Function(Int64)>()
int functionHashes(int count) {
  final Identity generic = identity;
  final closure = counter(1), box = Box<int>(2);
  final method = box.choose, make = Box.new, alias = PhantomBox.new;
  final applied = generic<int>, closed = closure<int>;
  final bound = method<int>, constructor = make<int>;
  final phantom = alias<int, String>, nested = nestedParcelFor<int>();
  final staticHash = applied.hashCode, closureHash = closed.hashCode;
  final methodHash = bound.hashCode, constructorHash = constructor.hashCode;
  final phantomHash = phantom.hashCode, nestedHash = nested.hashCode;
  collect(count);
  var flags = 0;
  if (sameFunction(applied, identity<int>) && applied.hashCode == staticHash) {
    flags |= 1;
  }
  if (sameFunction(closed, closure<int>) && closed.hashCode == closureHash) {
    flags |= 2;
  }
  if (sameFunction(bound, box.bind()) && bound.hashCode == methodHash) {
    flags |= 4;
  }
  if (sameFunction(constructor, Box<int>.new) &&
      constructor.hashCode == constructorHash) {
    flags |= 8;
  }
  if (sameFunction(phantom, phantomBox<int, String>) &&
      phantom.hashCode == phantomHash &&
      phantom != (alias<int, bool>) &&
      phantom != constructor) {
    flags |= 16;
  }
  if (sameFunction(nested, Parcel<Parcel<int>?>.new) &&
      nested.hashCode == nestedHash) {
    flags |= 32;
  }
  return flags;
}

bool sameType<T>(Type expected, int count) {
  final Object actual = T;
  final hash = actual.hashCode;
  collect(count);
  return actual == expected &&
      hash == expected.hashCode &&
      actual.hashCode == hash;
}

@Export<Int64 Function(Int64)>()
int typeHashes(int count) =>
    (sameType<Identity>(RenamedIdentity, count) ? 1 : 0) |
    (sameType<Box<Identity>>(Box<RenamedIdentity>, count) ? 2 : 0) |
    (sameType<Identity>(identity.runtimeType, count) ? 4 : 0) |
    (sameType<Never?>(Null, count) ? 8 : 0) |
    (sameType<Parcel<int>?>(typeOf<Parcel<int>?>(), count) ? 16 : 0);

Type typeOf<T>() => T;

int events = 0;
T throwing<T>(T value) {
  events = 2;
  throw value as Object;
}

int useThrow(Identity generic, int count) {
  final applied = generic<int>;
  collect(count);
  try {
    events = 1;
    applied(4);
  } on int catch (value) {
    events = events * 10 + value;
  } finally {
    events = events * 10 + 5;
  }
  return events;
}

@Export<Int64 Function(Int64)>()
int exceptions(int count) => useThrow(throwing, count);

abstract class Package<T> {
  factory make(T value, {int mark}) = Parcel<T>;
  T get value;
  int get mark;
}

class Parcel<T>(@override final T value, {@override final int mark = 7})
    implements Package<T> {
  new named(T value, {int mark = 9}) : this(value, mark: mark);
}

typedef ParcelMaker<T> = Parcel<T> Function(T, {int mark});
typedef PhantomParcel<T, S> = Parcel<T>;
ParcelMaker<T> parcelFor<T>() => Parcel<T>.new;
ParcelMaker<T> inferredParcelFor<T>() => Parcel.new;
ParcelMaker<T> namedParcelFor<T>() => Parcel<T>.named;
ParcelMaker<int> phantomParcelFor<T>() => PhantomParcel<int, T>.new;
ParcelMaker<Parcel<T>?> nestedParcelFor<T>() => Parcel<Parcel<T>?>.new;
ParcelMaker<T> Function() closedParcelFor<T>() =>
    () => Parcel<T>.new;
Package<T> Function(T, {int mark}) packageFor<T>() => Package<T>.make;

class Maker<T>() {
  final ParcelMaker<T> stored = Parcel<T>.new;
  late final ParcelMaker<T> lazy = Parcel<T>.new;
  ParcelMaker<T> get make => Parcel<T>.new;
  ParcelMaker<T> method() => Parcel<T>.new;
}

class IntMaker() extends Maker<int>;

extension type Token<T>(T value);
Token<T> Function(T) tokenFor<T>() => Token<T>.new;

@Export<Int64 Function(Int64)>()
int lexicalConstructors(int count) {
  final direct = parcelFor<int>(), inferred = inferredParcelFor<int>();
  final named = namedParcelFor<int>(), phantom = phantomParcelFor<String>();
  final nested = nestedParcelFor<int>(), closed = closedParcelFor<int>()();
  final owner = IntMaker();
  final inherited = owner.make, factory = packageFor<int>();
  final token = tokenFor<int>();
  collect(count);
  final Object actual = nested;
  return (direct == Parcel<int>.new &&
              direct == inferred &&
              direct == inherited &&
              direct == owner.stored &&
              direct == owner.lazy &&
              direct == owner.method() &&
              direct == closed &&
              direct == phantom &&
              named == Parcel<int>.named &&
              factory == Package<int>.make &&
              factory != direct
          ? 1000000
          : 0) +
      (actual is ParcelMaker<Parcel<int>?> ? 100000 : 0) +
      direct(1).mark * 10000 +
      named(2).mark * 1000 +
      factory(3).mark * 100 +
      nested(direct(4), mark: 5).value!.value * 10 +
      token(6).value;
}

ParcelMaker<Parcel<int>?>? savedConstructor;
int savedHash = 0;

@Export<Int64 Function(Int64)>()
int keepConstructor(int count) {
  savedConstructor = nestedParcelFor<int>();
  savedHash = savedConstructor.hashCode;
  collect(count);
  return savedConstructor == Parcel<Parcel<int>?>.new ? 1 : 0;
}

@Export<Int64 Function(Int64)>()
int callConstructor(int count) {
  final make = savedConstructor!;
  collect(count);
  return make.hashCode == savedHash
      ? make(Parcel<int>(4)).value!.value * 10 + make(null).mark
      : 0;
}

class Broken<T>(T value) {
  this {
    events = events * 10 + 2;
    throw value as Object;
  }
}

Broken<T> Function(T) brokenFor<T>() => Broken<T>.new;
int constructorArgument(int value) {
  events = events * 10 + 1;
  return value;
}

@Export<Int64 Function(Int64)>()
int constructorFailures(int count) {
  events = 0;
  final make = brokenFor<int>();
  collect(count);
  try {
    make(constructorArgument(4));
  } on int catch (value) {
    events = events * 10 + value;
  } finally {
    events = events * 10 + 5;
  }
  final thrown = events;
  final Maker<num> maker = IntMaker();
  var checks = 0;
  for (var kind = 0; kind < 4; kind++) {
    events = 0;
    try {
      final make = switch (kind) {
        0 => maker.make,
        1 => maker.stored,
        2 => maker.lazy,
        _ => maker.method(),
      };
      events = 1;
      collect(count);
      make(1.5);
      return -1;
    } on TypeError {
      checks = checks * 10 + events;
    }
  }
  return thrown * 10 + checks;
}
