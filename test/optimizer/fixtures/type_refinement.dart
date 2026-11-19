final class Receiver(final int value) {
  int read() => value;
}

int nullableGuard(bool selected) {
  final receiver = selected ? Receiver(7) : null;
  if (receiver != null) return receiver.read();
  return 3;
}

int nullAssertion(bool selected) {
  final receiver = selected ? Receiver(7) : null;
  try {
    return receiver!.read();
  } on TypeError {
    return 43;
  }
}

int matches<T>(Object? value) {
  if (value is T) return value is int ? 11 : 17;
  return 23;
}

int genericChecks(bool selected) {
  final Object value = selected ? 7 : 'other';
  return matches<int>(value) * 100 + matches<String>(value);
}

abstract class Reader() {
  int get count;
}

class const ConstantReader<T>() implements Reader {
  @override
  int get count => 3;
}

class StorageReader<T>() implements Reader {
  int get _storage => 7;
  @override
  int get count => _storage;
}

int readCount(Reader reader, bool selected) =>
    (selected ? const ConstantReader<int>() : reader).count;

class Bag<T>(final T item);

int readBag(Bag<Receiver> bag) => bag.item.read();

// Exercise a type test whose result depends on the generic caller.
// ignore: type_check_with_null
int nullResult<T>(T value) => value is Null ? 3 : 7;

int nonNullableInput(Object value) => nullResult<Object>(value);
int nullableInput(Object? value) => nullResult<Object?>(value);

abstract class Marker();
bool possibleInterface(Reader value) => value is Marker;

class DelegatingReader() {
  int read() => readValue();
  int readValue() => 1;
}

class IndependentReader() implements DelegatingReader {
  @override
  int read() => 3;

  @override
  int readValue() => 9;
}

int readOpen(DelegatingReader reader) => reader.read();
