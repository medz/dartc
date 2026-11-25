class A {
  int x = 1;
}

void main() {
  void t(void Function() f) {
    try {
      f();
    } catch (e) {
      print('${e.runtimeType}: $e');
    }
  }

  dynamic d = [
        [1, 2],
        (3, 4),
      ],
      i = 5,
      n = null;
  t(() {
    final [[m, _], (o, _)] = d;
    print(m + o);
  }); // expect: _TypeError: type 'List<Object>' is not a subtype of type 'List<Never>'
  t(() {
    final [int a, _] = d;
    print(a);
  }); // expect: _TypeError: type 'List<Object>' is not a subtype of type 'List<int>'
  t(() {
    final (int a, _) = (i, i);
    print(a);
  }); // expect: 5
  t(() {
    final (String a, _) = (i, i);
    print(a);
  }); // expect: _TypeError: type 'int' is not a subtype of type 'String'
  t(() {
    final (a, b) = i;
    print(a);
  }); // expect: _TypeError: type 'int' is not a subtype of type '(dynamic, dynamic)'
  t(() {
    final A(:x) = i;
    print(x);
  }); // expect: _TypeError: type 'int' is not a subtype of type 'A'
  t(() {
    final A(:x) = n;
    print(x);
  }); // expect: _TypeError: type 'Null' is not a subtype of type 'A'
  t(() {
    final {'a': x} = n;
    print(x);
  }); // expect: _TypeError: type 'Null' is not a subtype of type 'Map<dynamic, dynamic>'
  t(() {
    String s;
    (s,) = (i,);
    print(s);
  }); // expect: _TypeError: type 'int' is not a subtype of type 'String'
  t(() {
    int s;
    (s,) = (i,);
    print(s);
  }); // expect: 5
  t(() {
    final [String a] = [i];
    print(a);
  }); // expect: _TypeError: type 'int' is not a subtype of type 'String'
  t(() {
    final [a!] = [n];
    print(a);
  }); // expect: _TypeError: Null check operator used on a null value
  t(() {
    final [a as String] = [i];
    print(a);
  }); // expect: _TypeError: type 'int' is not a subtype of type 'String' in type cast
  t(() {
    for (final (int a, String b) in [(i, i)]) print(a);
  }); // expect: _TypeError: type 'int' is not a subtype of type 'String'
  t(() {
    var (a, [b]) = (1, <int>[]);
    print(b);
  }); // expect: StateError: Bad state: Pattern matching error
  t(() {
    var [String z, ...] = [i];
    print(z);
  }); // expect: _TypeError: type 'int' is not a subtype of type 'String'
  t(() {
    final (Object a, num b) = (i, n);
    print(b);
  }); // expect: _TypeError: type 'Null' is not a subtype of type 'num'
  t(() {
    final [(int, int) r] = [i];
    print(r);
  }); // expect: _TypeError: type 'int' is not a subtype of type '(int, int)'
}
