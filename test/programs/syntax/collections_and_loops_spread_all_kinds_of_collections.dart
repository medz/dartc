class It extends Iterable<int> {
  final String n;
  It(this.n);
  Iterator<int> get iterator {
    print('$n iterator');
    return [1, 2].iterator;
  }

  int get length {
    print('$n length');
    return 2;
  }
}

class EL implements List<int> {
  noSuchMethod(i) {
    print(i.memberName);
    if (i.memberName == #length) return 2;
    if (i.memberName == #iterator) return [5, 6].iterator;
    return null;
  }

  int operator [](int i) {
    print('[$i]');
    return i;
  }
}

class M implements Map<int, int> {
  noSuchMethod(i) {
    print(i.memberName);
    return null;
  }

  void forEach(void f(int a, int b)) {
    print('each');
    f(1, 2);
  }

  Iterable<MapEntry<int, int>> get entries {
    print('entries');
    return [MapEntry(3, 4)];
  }
}

void main() {
  print([...It('a')]);
  // expect: a iterator
  // expect: [1, 2]
  print([0, ...It('b')]);
  // expect: b iterator
  // expect: [0, 1, 2]
  print([...It('c'), 9]);
  // expect: c iterator
  // expect: [1, 2, 9]
  List<num> l = [...It('d')]; // expect: d iterator
  print(l); // expect: [1, 2]
  print({...It('e')});
  // expect: e iterator
  // expect: {1, 2}
  print({0, ...It('f')});
  // expect: f iterator
  // expect: {0, 1, 2}
  Iterable? n;
  print([1, ...?n]); // expect: [1]
  Iterable<int>? m = It('g');
  print([...?m]);
  // expect: g iterator
  // expect: [1, 2]
  dynamic d = It('h');
  print(<int>[...d]);
  // expect: h iterator
  // expect: [1, 2]
  Iterable<Object> o = It('i');
  print(<int>[...o.cast<int>()]);
  // expect: i iterator
  // expect: [1, 2]
  print(<Object>[...o]);
  // expect: i iterator
  // expect: [1, 2]
  try {
    Iterable<Object> bad = ['x'];
    print(<int>[...(bad as dynamic)]);
  } catch (e) {
    print(e);
  }
  // expect: type 'String' is not a subtype of type 'int'
  print({...M()});
  // expect: each
  // expect: {1: 2}
  print({0: 1, ...M()});
  // expect: each
  // expect: {0: 1, 1: 2}
  dynamic dm = M();
  print(<int, int>{...dm});
  // expect: entries
  // expect: {3: 4}
  print([...EL()]);
  // expect: Symbol("length")
  // expect: Symbol("iterator")
  // expect: [5, 6]
  print({...EL()});
  // expect: Symbol("iterator")
  // expect: {5, 6}
  final self = [1, 2];
  print([...self, ...self]); // expect: [1, 2, 1, 2]
  print([
    for (var i = 0; i < 2; i++) ...[i, i],
  ]); // expect: [0, 0, 1, 1]
  print([if (self.length > 1) ...It('j') else 4]);
  // expect: j iterator
  // expect: [1, 2]
}
