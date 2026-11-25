extension type const Base<T>(int value) {
  bool accepts(Object? input) => input is T;
  bool Function(Object?) capture() =>
      (input) => input is T;
  int get doubled => value * 2;
  bool again(Object? x) => accepts(x) && this.accepts(x);
  Type get kind => T;
}

extension type const Middle<A>(int value) implements Base<List<A>> {
  bool inner(Object? x) => accepts(x);
  Type own() => kind;
}

extension type Leaf<B>(int value) implements Middle<B> {
  int own2() => doubled + this.value;
  bool Function(Object?) c() => capture();
  Leaf.two(B a, this.value) {
    print(kind);
  }
}

class Cell<T> {
  final T item;
  Cell(this.item);
}

extension CellX<T> on Cell<T> {
  bool get isInt => T == int;
  bool operator >(int o) => T == int;
}

extension type W<T>(T v) {
  Type get kind => T;
}

void main() {
  print((
    Base<int>(1).again(2),
    Base<int>(1).again('a'),
    Middle<int>(1).inner([1]),
    Middle<int>(1).inner(['a']),
    Middle<String>(1).own(),
    Leaf<int>(2).own2(),
    Leaf<int>(2).c()([3]),
    Leaf<int>(2).c()(3),
  )); // expect: (true, false, true, false, List<String>, 6, true, false)
  Leaf.two('a', 3); // expect: List<String>
  Object cell = Cell<int>(1);
  print(switch (cell) {
    Cell<num>(isInt: true) => 0,
    Cell<int>(isInt: true) => 1,
    _ => 2,
  }); // expect: 1
  print(switch (cell) {
    Cell<num>() && > 0 => 0,
    Cell<int>() && > 0 => 1,
    _ => 2,
  }); // expect: 1
  Object o = 3;
  print(switch (o) {
    W<num>(kind: == int) => 0,
    W<int>(kind: == int) => 1,
    _ => 2,
  }); // expect: 1
}
