Never n() => throw 'n';

class A {
  Never get g => n();
  Never operator +(int x) => throw 'op';
  Never operator [](int x) => throw 'at';
  Never operator -() => throw 'minus';
  Never call(int x) => throw 'call';
  Never m() => throw 'm';
  set s(Never x) {}
}

void f(Never x) {}
void named({Never? x, required int y}) => print((x, y));
Future<Never> later() async => throw 'f';
T id<T>(T t) => t;
Never nested(Never Function() f) => f();

class G<T> {
  T get v => throw 'G';
  T m(T t) => t;
}

class H extends G<Never> {
  late Never field;
  Never? maybe;
}

void go(Object? Function() f) {
  try {
    print(f());
  } catch (e) {
    print('$e');
  }
}

Future<void> main() async {
  go(() {
    Never x = n();
    return x;
  }); // expect: n
  go(() {
    final x = n();
    return x;
  }); // expect: n
  go(() {
    var x = n();
    x = n();
    return x;
  }); // expect: n
  go(() => A().g); // expect: n
  go(() => A() + 1); // expect: op
  go(() => A()[1]); // expect: at
  go(() => -A()); // expect: minus
  go(() => A()(1)); // expect: call
  go(() => A().m()); // expect: m
  go(() => n() + 1); // expect: n
  go(() => n().foo); // expect: n
  go(() => n() == 1); // expect: n
  go(() => [n()]); // expect: n
  go(() => {'a': n()}); // expect: n
  go(() => (n(), 1)); // expect: n
  go(() => '${n()}'); // expect: n
  go(() => !n()); // expect: n
  go(() => n() as int); // expect: n
  go(() => n() is int); // expect: n
  go(() => n() ?? 1); // expect: n
  go(() => n() ? 1 : 2); // expect: n
  go(() => f(n())); // expect: n
  go(() => named(y: 1));
  // expect: (null, 1)
  // expect: null
  go(() => named(x: null, y: 2));
  // expect: (null, 2)
  // expect: null
  go(() => id<Never>(n())); // expect: n
  go(() => nested(n)); // expect: n
  go(() => A().s = n()); // expect: n
  go(() => G<Never>().v); // expect: G
  go(() => H().v); // expect: G
  go(() => H().m(n())); // expect: n
  go(() => H().field); // expect: LateInitializationError: Field 'field' has not been initialized.
  go(() => H().maybe); // expect: null
  go(() => (A() as dynamic).s = 1); // expect: type 'int' is not a subtype of type 'Never' of 'x'
  go(() => (f as dynamic)(1)); // expect: type 'int' is not a subtype of type 'Never' of 'x'
  go(() => (f as dynamic)(null)); // expect: type 'Null' is not a subtype of type 'Never' of 'x'
  for (final x in <Never>[]) {
    print(x);
  }
  for (Never x in <Never>[]) {
    print(x);
  }
  try {
    final x = await later();
    print(x);
  } catch (e) {
    print(e);
  }
  // expect: f
  try {
    await for (final x in Stream<Never>.error('s')) {
      print(x);
    }
  } catch (e) {
    print(e);
  }
  // expect: s
  go(() {
    switch (n()) {
      case final x:
        return x;
    }
  }); // expect: n
  go(() {
    final (a, b) = (1, n());
    return (a, b);
  }); // expect: n
  go(() {
    if (n() case final x) return x;
    return 1;
  }); // expect: n
  go(() {
    if (<Never>[] case [final x]) return x;
    return 'empty';
  }); // expect: empty
  go(
    () => switch (<Never>[]) {
      [final x, ...] => x,
      _ => 'none',
    },
  ); // expect: none
  go(() {
    Never Function(Never) g = (Never x) => x;
    return g is Never Function(Never);
  }); // expect: true
  print('end'); // expect: end
}
