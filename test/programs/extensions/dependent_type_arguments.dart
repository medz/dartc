extension E<A, B extends List<A>, C extends Iterable<B>, D> on List<A> {
  (Type, Type, Type, Type) get bounds => (A, B, C, D);
  Type argument() => B;
  (Type, B) collect(A value) => (B, <A>[value] as B);

  void show() {
    print(bounds);
    print(this.bounds);
    final implicit = argument;
    final explicit = this.argument;
    print((implicit(), explicit()));
  }
}

void show<A>(List<A> values) {
  print(values.bounds);
  print(E(values).bounds);
}

void main() {
  print(<int>[].bounds);
  // expect: (int, List<int>, Iterable<List<int>>, dynamic)
  print(E(<int>[]).bounds);
  // expect: (int, List<int>, Iterable<List<int>>, dynamic)
  final (Type, List<int>) Function(int) implicitCollect = <int>[].collect;
  final (Type, List<int>) Function(int) namedCollect = E(<int>[]).collect;
  print((
    implicitCollect(1),
    namedCollect(2),
  )); // expect: ((List<int>, [1]), (List<int>, [2]))
  final implicit = <int>[].argument;
  final explicit = E(<int>[]).argument;
  print((implicit(), explicit())); // expect: (List<int>, List<int>)
  E<num, List<int>, Set<List<int>>, bool>(<int>[]).show();
  // expect: (num, List<int>, Set<List<int>>, bool)
  // expect: (num, List<num>, Iterable<List<num>>, dynamic)
  // expect: (List<int>, List<num>)
  show(<String>[]);
  // expect: (String, List<String>, Iterable<List<String>>, dynamic)
  // expect: (String, List<String>, Iterable<List<String>>, dynamic)
}
