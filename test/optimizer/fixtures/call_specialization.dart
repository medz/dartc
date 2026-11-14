final class Box<T>(var T value);

T retain<T>(T value) => value;

int forward(int value) {
  final box = Box(value);
  box.value = retain(value + 1);
  return box.value;
}

int rejectedWrite() {
  final Box<num> box = Box<int>(3);
  try {
    box.value = 1.5;
  } on TypeError {
    return box.value.toInt();
  }
  return -1;
}

class Parent() {
  int read([int value = 1]) => value;
}

final class Child() extends Parent {
  int add(int value) => value + 3;

  @override
  int read([int value = 7]) => value;
}

int defaultArgument() => Child().read();

int dispatch(int value) => Child().add(value);
