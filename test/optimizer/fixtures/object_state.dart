typedef Operation = int Function(int);

final class Box<T>(T initial) {
  T value = initial;
}

Box<T> replace<T>(Box<T> box, T value) {
  box.value = value;
  return box;
}

int increment(int value) => value + 1;
int twice(int value) => value * 2;
int unused(int value) => throw StateError('overwritten initializer');
Operation saved = unused;
int invokeSaved(int value) => saved(value);

String evaluate(bool first) {
  final left = Box(1), right = Box(2);
  final selected = first ? left : right;
  final alias = replace(selected, 7);
  var captured = 0;
  int read() => captured;
  captured = alias.value;
  saved = first ? increment : twice;
  return '${left.value}:${right.value}:${read()}:${invokeSaved(3)}';
}

int forwardCaptured(int value) {
  final box = Box(value);
  var captured = box.value;
  int read() => captured;
  captured = value;
  return read();
}

int selectStored(bool first, int left, int right) {
  final box = Box(left);
  if (first) {
    box.value = left + 1;
  } else {
    box.value = right * 2;
  }
  return box.value;
}

int accumulate(int count, int seed) {
  final box = Box(seed);
  for (var i = 0; i < count; i++) {
    box.value += i;
  }
  return box.value;
}

void main(List<String> arguments) => print(evaluate(arguments.isEmpty));
