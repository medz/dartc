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

int Function() makeCounter(int initial) {
  var value = initial;
  return () => ++value;
}

int returnedClosures() {
  final first = makeCounter(3);
  final second = makeCounter(3);
  return first() * 100 + second();
}

int recursiveValue(int n) {
  if (n == 0) return observed;
  observed = 9;
  return recursiveValue(n - 1);
}

int recursionEffect(int n) {
  observed = 3;
  recursiveValue(n);
  return observed;
}

int dynamicEffects() {
  observed = 3;
  dynamic box = Box<int>(1);
  box.update(7);
  return observed;
}

int dynamicRejectedArgument() {
  observed = 3;
  dynamic box = Box<int>(1);
  try {
    box.update('wrong');
  } catch (_) {
    return observed;
  }
  return -1;
}

class Missing {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    observed = 41;
    return 7;
  }
}

int noSuchMethodEffects() {
  observed = 3;
  dynamic value = Missing();
  final int answer = value.absent();
  return observed + answer;
}

int addAndObserve(int value) {
  observed = value;
  return value + 1;
}

int dynamicFunctionValue() {
  observed = 3;
  dynamic function = addAndObserve;
  final int value = function(7);
  return observed + value;
}

int dynamicFunctionRejectsArgument() {
  observed = 3;
  dynamic function = addAndObserve;
  try {
    function('wrong');
  } catch (_) {
    return observed;
  }
  return -1;
}

int dynamicMethodValue() {
  observed = 3;
  dynamic box = Box<int>(1);
  dynamic update = box.update;
  update(7);
  return observed;
}

class ReturnsSeven {
  int answer() => 7;
}

int nullableDynamic(ReturnsSeven? value) => (value as dynamic).answer();

int hiddenIncrement(int value) => value + 1;

void exposePrivateArgument(void Function(int Function()) boundary) {
  final hidden = hiddenIncrement;
  boundary(() => hidden(7));
}

void exposeInstantiatedClosure(void Function(int Function(int)) boundary) {
  T local<T>(T value) => value;
  boundary(local<int>);
}

class GenericMethod() {
  T echo<T>(T value) => value;
  int kind<T>() => T == int ? 17 : 29;
}

void exposeInstantiatedMethod(void Function(int Function(int)) boundary) {
  boundary(GenericMethod().echo<int>);
}

int genericBoundMethodValue() {
  final kind = GenericMethod().kind<int>;
  return kind();
}

int genericBoundMethodOtherType() {
  final kind = GenericMethod().kind<String>;
  return kind();
}

int constructedCallback() => 23;

class CallbackProduct<T>() {
  final Type kind = T;
  final int Function() callback = constructedCallback;
}

void exposeConstructor(
  void Function(CallbackProduct<int> Function()) boundary,
) {
  boundary(CallbackProduct<int>.new);
}

class ExternalSlot() {
  int Function()? callback;
}

void publishCallback(ExternalSlot destination) {
  destination.callback = constructedCallback;
}

Never throwProduct() => throw CallbackProduct<int>();

void exposeThrowingFunction(void Function(Never Function()) boundary) {
  boundary(throwProduct);
}

int unexposedCallback() => 41;

class FailingProduct() {
  final int Function() callback = unexposedCallback;
  this {
    throw 7;
  }
}

void exposeFailingConstructor(
  void Function(FailingProduct Function()) boundary,
) {
  boundary(FailingProduct.new);
}

void exposeUnappliedConstructor(
  void Function(CallbackProduct<T> Function<T>()) boundary,
) {
  boundary(CallbackProduct.new);
}
