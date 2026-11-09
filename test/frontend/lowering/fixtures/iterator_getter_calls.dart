import 'effects.dart';

int listZeroCall() {
  final iterator = <int Function()>[() => tick(30)].iterator;
  iterator.moveNext();
  return iterator.current();
}

int listArgumentCall() {
  final iterator = <int Function(int)>[(value) => tick(value + 20)].iterator;
  iterator.moveNext();
  return iterator.current(tick(1));
}

class CallbackCursor() implements Iterator<int Function(int, {int add})> {
  @override
  int Function(int, {int add}) get current {
    tick(10);
    return (int value, {int add = 0}) => tick(value + add + 20);
  }

  @override
  bool moveNext() => true;
}

class ZeroCursor() implements Iterator<int Function()> {
  @override
  int Function() get current {
    tick(10);
    return () => tick(20);
  }

  @override
  bool moveNext() => true;
}

int customArgumentCall(int value) {
  final Iterator<int Function(int, {int add})> iterator = CallbackCursor();
  try {
    return iterator.current(tick(value), add: tick(2));
  } on StateError {
    return 9;
  }
}

int customZeroCall() {
  final Iterator<int Function()> iterator = ZeroCursor();
  return iterator.current();
}

int extractedCall() {
  final Iterator<int Function(int, {int add})> iterator = CallbackCursor();
  final function = iterator.current;
  return function(tick(1), add: tick(2));
}
