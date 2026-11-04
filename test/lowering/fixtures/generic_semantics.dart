// Deliberately exercise total patterns and generic type checks.
// ignore_for_file: unnecessary_type_check, unnecessary_type_name_in_constructor, dead_code, use_primary_constructors
import 'effects.dart';

abstract class Readable<T> {
  T get item;
}

class Envelope<T> implements Readable<T> {
  final T stored;
  Envelope(this.stored);
  Envelope.named(this.stored);
  @override
  T get item {
    tick(101);
    return stored;
  }
}

typedef Wrapped<T> = Envelope<T>;
typedef IntWrapped = Wrapped<int>;
typedef Reader<T> = Readable<T>;

int genericObjectPattern(int seed) {
  final Object value = Envelope<int>(seed);
  return switch (value) {
    Envelope<String>(item: _) => -10,
    Envelope<int>(item: > 0) && Envelope<int>(item: var item) => item,
    Envelope<int>(item: var item) => item - 10,
    _ => -100,
  };
}

int genericRecordPattern(int seed) {
  final value = (Envelope<int>(seed), Wrapped<String>('ok'));
  if (value case (
    Envelope<int>(item: > 0 && var item),
    Wrapped<String>(item: 'ok'),
  )) {
    return item;
  }
  return -10;
}

int genericGetterCache(int seed) {
  final Object value = Envelope<int>(seed);
  return switch (value) {
    Envelope<num>(item: var item) when probe(0) => item as int,
    Envelope<int>(item: > 0) && Envelope<int>(item: var item) => item,
    Envelope<int>(item: var item) => item - 10,
    _ => -100,
  };
}

int genericAlias(int seed) {
  final Wrapped<int> value = IntWrapped(seed);
  final Reader<num> view = value;
  final Object object = value;
  return (view.item as int) +
      (object is Wrapped<int> && object is! Wrapped<String> ? 10 : 0);
}

int genericDotConstructor(int seed) {
  final Envelope<int> first = .new(seed);
  final Wrapped<int> second = .named(seed + 1);
  return first.item + second.item;
}

int genericInterfaceCast(int seed, bool valid) {
  final Object value = valid ? Envelope<int>(seed) : Envelope<String>('wrong');
  try {
    final Reader<num> view = value as Reader<num>;
    return view.item as int;
  } on TypeError {
    return -100;
  }
}

bool genericInterfaceTests(int seed) {
  final Object value = Envelope<int>(seed);
  return value is Readable<int> &&
      value is Reader<num> &&
      value is! Reader<String> &&
      value is Envelope<num> &&
      value is! Envelope<String>;
}

int genericInterfacePattern(int seed) {
  final Object value = Wrapped<int>(seed);
  if (value case Reader<num>(item: int item)) return item;
  return -100;
}

class Lens<T> {
  bool matches(Object value) => switch (value) {
    Envelope<T>(item: var item) => item is T,
    _ => false,
  };
}

bool genericBodyPattern(int seed) {
  final Object value = Envelope<int>(seed);
  return Lens<int>().matches(value) &&
      Lens<num>().matches(value) &&
      !Lens<String>().matches(value);
}

int genericNullablePattern(int seed) {
  final Object value = Envelope<int?>(seed == 0 ? null : seed);
  if (value case Envelope<int?>(item: var item?)) return item;
  return -100;
}

int genericRecordCache(int seed) {
  final value = (Envelope<int>(seed), 5);
  if (value
      case (Envelope<int>(item: 0), var result) ||
          (Envelope<int>(item: var result), _)) {
    return result;
  }
  return -100;
}
