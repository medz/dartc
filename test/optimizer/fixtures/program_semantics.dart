int observed = 0;

class Box<T> {
  Box(this.value);
  T value;

  void update(T next) {
    observed = 99;
    value = next;
  }
}

class Counted {
  Counted(this.value) {
    observed = value;
  }
  final int value;
}

int rejectedCovariantCall() {
  observed = 3;
  final Box<Object> box = Box<int>(1);
  try {
    box.update('wrong');
  } catch (_) {
    return observed;
  }
  return -1;
}

int constructorValue() {
  observed = 1;
  final make = Counted.new;
  final value = make(7);
  return observed + value.value;
}

T identity<T>(T value) => value;

int genericFunctionValue() {
  final apply = identity<int>;
  return apply(9);
}

int genericClosureValue() {
  T nested<T>(T value) => value;
  final apply = nested<int>;
  return apply(17);
}

Box<T> genericFactory<T>(T value) {
  final make = Box<T>.new;
  return make(value);
}

int genericConstructorValue() => genericFactory<int>(23).value;

Future<int> completed() async => 7;
Future<int> futureValue() => completed();

int boundMethodValue() {
  final box = Box<int>(5);
  final update = box.update;
  update(7);
  return box.value;
}
