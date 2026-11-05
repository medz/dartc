import 'effects.dart';

int total(Iterable<int> values) {
  var result = 0;
  for (final value in values) {
    result = result * 10 + value;
  }
  return result;
}

extension Sequences<T> on List<T> {
  Iterable<T> repeated(int count) sync* {
    tick(1);
    for (var i = 0; i < count; i++) {
      yield* this;
    }
  }

  Iterable<U> mapped<U>(U Function(T) map) sync* {
    for (final value in this) {
      yield map(value);
    }
  }
}

extension type Piece<T>(T value) {
  Iterable<T> one() sync* {
    tick(2);
    yield value;
  }

  Iterable<U> mapped<U>(U Function(T) map) sync* {
    yield map(value);
  }

  Iterable<T> nested() {
    Iterable<T> local() sync* {
      yield value;
    }

    return local();
  }
}

class Producer<T>(final T value) {
  Iterable<T> values(T input) sync* {
    tick(3);
    yield value;
    yield input;
  }

  Iterable<T> nested() {
    Iterable<T> local() sync* {
      yield value;
    }

    return local();
  }
}

int ordinaryExtensionGenerators() {
  final values = <int>[1, 2];
  final repeated = values.repeated;
  final mapped = values.mapped;
  return total(repeated(2)) + total(mapped<int>((value) => value + 5));
}

int extensionTypeGenerators() {
  final piece = Piece<int>(4);
  final one = piece.one;
  final mapped = piece.mapped;
  return total(one()) +
      total(mapped<int>((value) => value + 2)) +
      total(piece.nested());
}

int genericClassGeneratorCapture() {
  final values = Producer<int>(4).nested();
  return total(values) + total(values);
}

int patternGenerator() => matchGenerator(Piece<int>(3));

int matchGenerator(Object? value) {
  if (value case Piece<int>(one: final create)) {
    return total(create());
  }
  return -1;
}

int covariantGeneratorEntry(bool tearOff) {
  final Producer<num> producer = Producer<int>(1);
  tick(4);
  try {
    if (tearOff) {
      dynamic call = producer.values;
      call(1.5);
    } else {
      producer.values(1.5);
    }
    return tick(5);
  } on TypeError {
    return tick(6);
  }
}
