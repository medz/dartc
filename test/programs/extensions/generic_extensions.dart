extension Lists<T> on List<T> {
  T get middle => this[length ~/ 2];
  List<R> both<R>(R Function(T value) make) => [for (final e in this) make(e)];
  Type get type => T;
  bool holds(Object? value) => value is T;
  List<T> copy() => [...this];
  void twice() {
    add(first);
    add(this.last);
  }

  Map<T, R> paired<R>(R value) => {for (final e in this) e: value};
  Type Function() get later =>
      () => T;
  Type pair<R>() => Map<T, R>;
}

extension Compare<T extends Comparable<T>> on T {
  T orMore(T other) => compareTo(other) < 0 ? other : this;
}

extension Run<T> on T {
  R let<R>(R Function(T it) work) => work(this);
  T also(void Function(T it) work) {
    work(this);
    return this;
  }
}

extension Compose<A, B> on B Function(A) {
  C Function(A) then<C>(C Function(B) next) =>
      (a) => next(this(a));
}

class Box<T> {
  final T value;
  Box(this.value);
  Type inner() => [value].type;
  String show() => describe('!');
}

extension on Box<num> {
  String describe(String end) => 'box of $value$end';
}

extension BoxOf<T> on Box<T> {
  String describe(String end) => 'some $value$end';
}

void main() {
  final list = [1, 2, 3];
  print(list.middle); // expect: 2
  print(list.type); // expect: int
  print(list.holds('x')); // expect: false
  print(list.holds(1)); // expect: true
  print(list.both((n) => '$n!')); // expect: [1!, 2!, 3!]
  print(list.copy().runtimeType); // expect: List<int>
  print((list..twice())); // expect: [1, 2, 3, 1, 1]
  print(['a'].paired(2.5).runtimeType); // expect: _Map<String, double>
  print(<num>[1, 2].later()); // expect: num
  print(['x'].pair<bool>()); // expect: Map<String, bool>
  print('a'.orMore('b')); // expect: b
  print(3.let((it) => it + 1)); // expect: 4
  print('q'.let((it) => it.length)); // expect: 1
  final half = ((int n) => n / 2).then((d) => 'it is $d');
  print(half(5)); // expect: it is 2.5
  print(Box(3).inner()); // expect: int
  print(Box('s').show()); // expect: some s!
  print(Box(2).show()); // expect: some 2!
  print(Lists<Object>(list).type); // expect: Object
  final tear = list.both;
  print(tear<int>((n) => n * n)); // expect: [1, 4, 9, 1, 1]
  print(Run(8).also((it) => print('also $it')));
  // expect: also 8
  // expect: 8
  List<Object> other = <String>['s'];
  print(other.type); // expect: Object
  print(other.holds(3)); // expect: true
}
