extension type Wrap<T>(T inner) {
  Type get type => T;
  Wrap<R> map<R>(R Function(T) f) => Wrap(f(inner));
  bool fits(Object? o) => o is T;
  T get get => inner;
}

extension type More<T>(Wrap<T> it) implements Wrap<T> {
  T get again => it.inner;
}

extension type Positive._(int n) {
  Positive(this.n) {
    if (n < 0) throw ArgumentError('negative');
  }
}

extension type Maybe<T>(T? value) {
  T or(T other) => value ?? other;
}

extension type Act(void Function(int) f) {
  void run() => f(4);
}

extension Shown on Positive {
  String get shown => '+$n';
}

void main() {
  final w = Wrap(3);
  print(w.type); // expect: int
  print(w.map((n) => 'v$n').inner); // expect: v3
  print(w.fits('x')); // expect: false
  print(w.map((n) => 'v').type); // expect: String
  final m = More(w);
  print(m.again); // expect: 3
  print(m.get); // expect: 3
  print(m.type); // expect: int
  print(Positive(4).shown); // expect: +4
  try {
    Positive(-1);
  } catch (e) {
    print(e);
  }
  // expect: Invalid argument(s): negative
  print(Maybe<int>(null).or(5)); // expect: 5
  print(Maybe(2).or(5)); // expect: 2
  Act((n) => print(n)).run(); // expect: 4
  dynamic d = w;
  print(d + 1); // expect: 4
  print(Wrap<num>(1).type); // expect: num
  print((Wrap<List<int>>([1])).inner.first); // expect: 1
  List<Wrap<int>> list = [w, Wrap(9)];
  print(list.map((e) => e.inner).toList()); // expect: [3, 9]
  print(list.runtimeType); // expect: List<int>
}
