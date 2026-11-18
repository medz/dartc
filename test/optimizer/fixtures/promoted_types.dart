class Box<T>(final T value);

int inspect<T>(T value) {
  if (value is int) {
    final box = Box(value);
    final record = (value,);
    final Object observedBox = box;
    final Object observedValue = value;
    return (observedBox is Box<int> ? 1 : 0) |
        (observedBox is Box<T> ? 2 : 0) |
        (record is (int,) ? 4 : 0) |
        (observedValue is int ? 8 : 0) |
        (box.value == value ? 16 : 0);
  }
  return 0;
}

int objectArgument(Object? value) => inspect<Object?>(value);

int integerArgument(int value) => inspect<int>(value);

bool observesBox<T>(T value) {
  if (value is int) return Box(value) is Box<int>;
  return false;
}

bool observesObjectArgument(Object? value) => observesBox<Object?>(value);

bool observesIntegerArgument(int value) => observesBox<int>(value);
