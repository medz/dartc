class P {
  Object? get seen {
    print('seen');
    return 1;
  }

  int get n {
    print('n');
    return 2;
  }
}

class L2 implements List<int> {
  noSuchMethod(i) {
    print(i.memberName);
    return 5;
  }

  int get length {
    print('length');
    return 2;
  }

  int operator [](int i) {
    print('[$i]');
    return i;
  }

  List<int> sublist(int a, [int? b]) {
    print('sublist $a $b');
    return [7];
  }
}

class M2 implements Map<String, int> {
  noSuchMethod(i) {
    print(i.memberName);
    return 5;
  }

  bool containsKey(Object? k) {
    print('has $k');
    return true;
  }

  int? operator [](Object? k) {
    print('[$k]');
    return 1;
  }
}

void t(String n, Object? Function() f) {
  print('-- $n');
  try {
    print(f());
  } catch (e) {
    print(e.runtimeType);
  }
}

void main() {
  Object l = L2();
  List<int> li = L2();
  Object m = M2();
  Map<String, int> mi = M2();
  Object o = P();
  t(
    'l int _',
    () => switch (l) {
      [int _, int _] => 1,
      _ => 2,
    },
  );
  // expect: -- l int _
  // expect: length
  // expect: [0]
  // expect: [1]
  // expect: 1
  t(
    'li int _',
    () => switch (li) {
      [int _, int _] => 1,
      _ => 2,
    },
  );
  // expect: -- li int _
  // expect: length
  // expect: [0]
  // expect: [1]
  // expect: 1
  t(
    'li _',
    () => switch (li) {
      [_, _] => 1,
      _ => 2,
    },
  );
  // expect: -- li _
  // expect: length
  // expect: 1
  t(
    'li var',
    () => switch (li) {
      [var a, _] => a,
      _ => 2,
    },
  );
  // expect: -- li var
  // expect: length
  // expect: [0]
  // expect: 0
  t(
    '&&',
    () => switch (li) {
      [(_ && _), (_ || 3)] => 1,
      _ => 2,
    },
  );
  // expect: -- &&
  // expect: length
  // expect: 1
  t(
    'or',
    () => switch (li) {
      [(3 || _), ((_))] => 1,
      _ => 2,
    },
  );
  // expect: -- or
  // expect: length
  // expect: [0]
  // expect: 1
  t(
    'q',
    () => switch (li) {
      [_?, _!] => 1,
      _ => 2,
    },
  );
  // expect: -- q
  // expect: length
  // expect: [0]
  // expect: [1]
  // expect: 1
  t(
    'as',
    () => switch (li) {
      [_ as int, _ as num] => 1,
      _ => 2,
    },
  );
  // expect: -- as
  // expect: length
  // expect: [0]
  // expect: [1]
  // expect: 1
  t(
    'rest',
    () => switch (li) {
      [_, ...] => 1,
      _ => 2,
    },
  );
  // expect: -- rest
  // expect: length
  // expect: 1
  t(
    'rest2',
    () => switch (li) {
      [..._, _] => 1,
      _ => 2,
    },
  );
  // expect: -- rest2
  // expect: length
  // expect: 1
  t(
    'rest3',
    () => switch (li) {
      [..., 1] => 1,
      _ => 2,
    },
  );
  // expect: -- rest3
  // expect: length
  // expect: [1]
  // expect: 1
  t(
    'rest4',
    () => switch (li) {
      [...List<int> _] => 1,
      _ => 2,
    },
  );
  // expect: -- rest4
  // expect: sublist 0 null
  // expect: 1
  t(
    'rest5',
    () => switch (li) {
      [...[_]] => 1,
      _ => 2,
    },
  );
  // expect: -- rest5
  // expect: sublist 0 null
  // expect: 1
  t(
    'rest6',
    () => switch (li) {
      [...(_ || [1])] => 1,
      _ => 2,
    },
  );
  // expect: -- rest6
  // expect: 1
  t(
    'obj',
    () => switch (l) {
      [...] => 1,
      _ => 2,
    },
  );
  // expect: -- obj
  // expect: 1
  t('decl', () {
    var [_, _] = li;
    return 1;
  });
  // expect: -- decl
  // expect: length
  // expect: 1
  t('decl2', () {
    var [a, ..._] = li;
    return a;
  });
  // expect: -- decl2
  // expect: length
  // expect: [0]
  // expect: 0
  t('decl3', () {
    var [...] = li;
    return 1;
  });
  // expect: -- decl3
  // expect: 1
  t(
    'm _',
    () => switch (m) {
      {'a': _} => 1,
      _ => 2,
    },
  );
  // expect: -- m _
  // expect: [a]
  // expect: 1
  t(
    'mi _',
    () => switch (mi) {
      {'a': _} => 1,
      _ => 2,
    },
  );
  // expect: -- mi _
  // expect: [a]
  // expect: 1
  t(
    'mi int _',
    () => switch (mi) {
      {'a': int _} => 1,
      _ => 2,
    },
  );
  // expect: -- mi int _
  // expect: [a]
  // expect: 1
  t(
    'mi var',
    () => switch (mi) {
      {'a': var x} => x,
      _ => 2,
    },
  );
  // expect: -- mi var
  // expect: [a]
  // expect: 1
  t(
    'mi or',
    () => switch (mi) {
      {'a': (_ || 3)} => 1,
      _ => 2,
    },
  );
  // expect: -- mi or
  // expect: [a]
  // expect: 1
  t(
    'mi 2',
    () => switch (mi) {
      {'a': 2} => 1,
      {'a': _} => 3,
      _ => 2,
    },
  );
  // expect: -- mi 2
  // expect: [a]
  // expect: 3
  t('m decl', () {
    var {'a': _} = mi;
    return 1;
  });
  // expect: -- m decl
  // expect: [a]
  // expect: 1
  t('m decl2', () {
    var {'a': b} = mi;
    return b;
  });
  // expect: -- m decl2
  // expect: [a]
  // expect: 1
  t(
    'P or2',
    () => switch (o) {
      P(seen: ((_) || 3)) => 1,
      _ => 2,
    },
  );
  // expect: -- P or2
  // expect: 1
  t(
    'P or3',
    () => switch (o) {
      P(seen: (var _ || 3)) => 1,
      _ => 2,
    },
  );
  // expect: -- P or3
  // expect: 1
  t(
    'P or4',
    () => switch (o) {
      P(seen: (Object? _ || 3)) => 1,
      _ => 2,
    },
  );
  // expect: -- P or4
  // expect: seen
  // expect: 1
  t(
    'P or5',
    () => switch (o) {
      P(n: (int _ || 3)) => 1,
      _ => 2,
    },
  );
  // expect: -- P or5
  // expect: n
  // expect: 1
  t(
    'P or6',
    () => switch (o) {
      P(n: (_ || 3) && 2) => 1,
      _ => 2,
    },
  );
  // expect: -- P or6
  // expect: n
  // expect: 1
  t(
    'P or7',
    () => switch (o) {
      P(n: ((_ && _) || 3)) => 1,
      _ => 2,
    },
  );
  // expect: -- P or7
  // expect: 1
  t(
    'P or8',
    () => switch (o) {
      P(n: ((_ || 4) || 3)) => 1,
      _ => 2,
    },
  );
  // expect: -- P or8
  // expect: 1
  t(
    'P or9',
    () => switch (o) {
      P(n: (_ || 4) && (_ || 5)) => 1,
      _ => 2,
    },
  );
  // expect: -- P or9
  // expect: 1
  t(
    'P cast',
    () => switch (o) {
      P(n: (_ as int) || 5) => 1,
      _ => 2,
    },
  );
  // expect: -- P cast
  // expect: n
  // expect: 1
  t(
    'P q',
    () => switch (o) {
      P(n: (_? || 5)) => 1,
      _ => 2,
    },
  );
  // expect: -- P q
  // expect: n
  // expect: 1
  t(
    'P obj2',
    () => switch (o) {
      P(n: int()) => 1,
      _ => 2,
    },
  );
  // expect: -- P obj2
  // expect: n
  // expect: 1
  t('P if', () {
    if (o case P(seen: _)) return 1;
    return 2;
  });
  // expect: -- P if
  // expect: seen
  // expect: 1
  t(
    'P in list',
    () => switch ([o]) {
      [P(seen: _)] => 1,
      _ => 2,
    },
  );
  // expect: -- P in list
  // expect: seen
  // expect: 1
  t(
    'dup',
    () => switch (o) {
      P(seen: 5) => 1,
      P(seen: _) => 3,
      _ => 2,
    },
  );
  // expect: -- dup
  // expect: seen
  // expect: 3
}
