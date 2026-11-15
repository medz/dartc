abstract class Message() {
  Object? get message;
  Object? get invalidValue;
}

class Counter(final int value) implements Message {
  int reads = 0;

  @override
  int get message {
    reads++;
    return value;
  }

  @override
  Object? get invalidValue => null;
}

int readMessage(Message error) {
  final message = error.message, value = error.invalidValue;
  if (message is int) return message;
  return value is int ? value : 0;
}

int privateCounter(int value) {
  final counter = Counter(value);
  return readMessage(counter) ^ counter.reads;
}

int calls = 0;

int incrementGlobal() => ++calls;

int readGlobal() => calls;

int Function() retainedCounter(int initial) {
  var value = initial;
  return () => ++value;
}

double deferredDouble(double value, int count) {
  double result;
  do {
    result = value;
    value += 1.0;
    count--;
  } while (count > 0);
  return result;
}
