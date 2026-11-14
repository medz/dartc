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

int add(int value, [int offset = 7]) => value + offset;

int staticValue(int value) {
  final apply = add;
  return apply(value);
}

int Function(int) adder(int initial) =>
    (value) => initial + value;

int capturedValue(int value) => adder(value)(9);

int sharedCapture(int value) {
  var current = value;
  int update(int next) => current += next;
  final apply = update;
  return apply(2) * 100 + apply(3);
}

int multipleCaptures(int value) {
  final first = adder(value), second = adder(value + 1);
  return first(2) * 10 + second(3);
}

int Function(int) captureType<T>(int value) =>
    (next) => T == int ? value + next : value - next;

int lexicalTypes(int value) =>
    captureType<int>(value)(3) + captureType<String>(value)(5);

int genericValue(int value) {
  T identity<T>(T input) => input;
  final apply = identity<int>;
  return apply(value);
}

final class MethodBox<T>(final int initial) {
  int apply<U>(int value) =>
      (T == int ? 10 : 20) + (U == String ? 100 : 200) + initial + value;
}

int boundValue(int value) {
  final first = MethodBox<int>(value).apply<String>;
  final second = MethodBox<String>(value + 1).apply<int>;
  return first(3) + second(5);
}

final class Pair<A, B>(final A first, final B second, {final int offset = 11});

typedef Flipped<A, B> = Pair<B, A>;

int aliasedConstructor(int value) {
  final make = Flipped<String, int>.new;
  final pair = make(value, 'kept', offset: 3);
  return pair.first + pair.offset;
}

abstract class Product<T> {
  factory(T value, {int offset}) = ConcreteProduct<T>;
  T get value;
  int get offset;
}

final class ConcreteProduct<T>(
  @override final T value, {
  @override final int offset = 11,
}) implements Product<T>;

int redirectedConstructor(int value) {
  final make = Product<int>.new;
  final product = make(value);
  return product.value + product.offset;
}

int checkedInput(int value) {
  if (value < 0) throw value;
  return value;
}

int throwingValue(int value) {
  final apply = checkedInput;
  try {
    return apply(value);
  } on int catch (error) {
    return error - 1;
  }
}

int unknownFunction(int Function(int) function, int value) => function(value);

int narrowedReceiver(int value) {
  final Parent receiver = Child();
  return receiver.read(value) + receiver.read();
}

final class GenericReceiver<T>() {
  int identify(int value) => value + (T == int ? 1 : 2);
}

int covariantReceiver(int value) {
  final GenericReceiver<num> receiver = GenericReceiver<int>();
  return receiver.identify(value);
}

final class EqualityBox(final int value) {
  @override
  bool operator ==(Object other) =>
      other is EqualityBox && other.value == value;

  @override
  int get hashCode => value;
}

int negatedEquality(int value) =>
    EqualityBox(value) != EqualityBox(value + 1) ? 7 : 9;
