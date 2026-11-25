void main<T>([List<String>? arguments]) {
  print((T, arguments));
  // expect: (dynamic, null)
  // expect: (num, List<num>, Iterable<List<num>>, 1, null)
  // expect: (num, List<num>, Iterable<List<num>>, 2, 3)
  // expect: (int, List<int>, List<List<int>>, 2, 3)
  // expect: type 'Comparable<dynamic>' is not a subtype of type 'Comparable<Comparable<dynamic>>' of 'T'
  // expect: [Code.first, Code.second]
  // expect: [Code.first, Code.second, FixedName.item]
  // expect: (-3, second, own, item, 0, 4)
  dynamic f = g;
  f(1);
  f(2, 3);
  f<int, List<int>, List<List<int>>>(2, 3);
  dynamic o = C();
  try {
    o.m();
  } catch (e) {
    print(e);
  }
  print(Code.values);
  print(const [Code.first, Code.second, FixedName.item]);
  print((
    Code.second.own,
    Code.second.name,
    FixedName.item.own,
    FixedName.item.name,
    FixedName.item.index,
    Named.a.own,
  ));
}

class C {
  void m<T extends Comparable<T>, S extends List<T>>() => print((T, S));
}

void g<T extends num, S extends List<T>, R extends Iterable<S>>([
  Object? a,
  Object? b,
]) => print((T, S, R, a, b));

enum Code {
  first(7),
  second.named(value: -3);

  const new(this._own);
  const new named({required int value}) : _own = value;
  final int _own;
  int get own => _own;
}

enum const FixedName() {
  item;

  final String _own = 'own';
  String get own => _own;
}

enum Named {
  a,
  b;

  final int _index = 4;
  const Named();
  int get own => _index;
}
