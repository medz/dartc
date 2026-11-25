// ignore_for_file: dead_code, receiver_of_type_never, invalid_null_aware_operator

Never n(String s) => throw s;

class A {
  Never get g => n('g');
  set g(Never x) => print('set');
  Never operator [](int i) => n('[]');
  void operator []=(int i, int v) => print('[]=');
  static Never get s => n('s');
}

class B extends A {
  @override
  Never get g => super.g;
  int plus() => super.g + 1;
}

abstract class I {
  int get v;
  int m(int x);
  bool operator <(int x);
}

class J implements I {
  Never get v => n('v');
  Never m(int x) => n('m');
  Never operator <(int x) => n('<');
}

T bound<T extends Never>(T Function() f) => f();
void use<T extends Never>(T Function() f) => f().anything;

Iterable<Never> generate() sync* {
  n('generate');
}

Stream<Never> stream() async* {
  yield n('stream');
}

extension E on String {
  Never get fails => n('E $this');
  Never operator +(int x) => n('E+ $this');
}

enum V {
  a;

  Never get v => n('V');
}

class Late {
  late final Never x = n('late');
  final int y;
  Late() : y = n('init');
  Late.other([Never? z]) : y = 1;
}

Never global = n('global');

void go(Object? Function() f) {
  try {
    print(f());
  } catch (e) {
    print('$e');
  }
}

void main() async {
  go(() => A()..g..g); // expect: g
  go(() => A().g = n('value')); // expect: value
  go(() => A().g.foo = 1); // expect: g
  go(() => A().g[1] = 1); // expect: g
  go(() => A().g[1]); // expect: g
  go(() => A().g()); // expect: g
  go(() => A().g++); // expect: g
  go(() => ++A().g); // expect: g
  go(() => A().g += 1); // expect: g
  go(() => A()[1] += 1); // expect: []
  go(() => A()[1] = 1);
  // expect: []=
  // expect: 1
  go(() => A().g?.foo); // expect: g
  go(() => A().g?.foo.bar()); // expect: g
  go(() => A().g.foo(1)[2].bar); // expect: g
  go(() => A().g!); // expect: g
  go(() => -A().g); // expect: g
  go(() => ~A().g); // expect: g
  go(() => A().g && true); // expect: g
  go(() => A().g || true); // expect: g
  go(() => A().g ?? n('never')); // expect: g
  go(() => true || A().g); // expect: true
  go(() => A.s); // expect: s
  go(() => A.s.foo); // expect: s
  go(() => B().g); // expect: g
  go(() => B().plus()); // expect: g
  I i = J();
  go(() => i.v + 1); // expect: v
  go(() => i.m(2) * 3); // expect: m
  go(() => i < 2); // expect: <
  go(() => bound(() => n('bound'))); // expect: bound
  go(() => use(() => n('use'))); // expect: use
  go(() => generate().toList()); // expect: generate
  go(() => 'x'.fails); // expect: E x
  go(() => 'x'.fails + 1); // expect: E x
  go(() => E('x') + 1); // expect: E+ x
  go(() => V.a.v); // expect: V
  go(() => Late()); // expect: init
  go(() => Late.other().x); // expect: late
  go(() => Late.other(n('argument'))); // expect: argument
  go(() => global); // expect: global
  go(() => <int>[for (final x in n('in')) x]); // expect: in
  go(() => [...n('spread')]); // expect: spread
  go(() => <int>{...?n('spread')}); // expect: spread
  go(() => {if (n('if')) 1: 2}); // expect: if
  go(() {
    if (n('if')) return 1;
    return 2;
  }); // expect: if
  go(() {
    while (n('while')) {}
  }); // expect: while
  go(() {
    for (final x in n('for')) {
      print(x);
    }
  }); // expect: for
  go(() {
    assert(n('assert'));
  }); // expect: null
  go(() => throw n('throw')); // expect: throw
  go(() => switch (n('switch')) {
    1 => 2,
    _ => 3,
  }); // expect: switch
  go(() => switch (1) {
    _ when n('when') => 2,
    _ => 3,
  }); // expect: when
  go(() {
    final (:x, :y) = n('record');
    return (x, y);
  }); // expect: record
  go(() {
    final [a, b] = n('list');
    return (a, b);
  }); // expect: list
  go(() {
    Object o = 1;
    if (o case Never x) return x;
    return 'no';
  }); // expect: no
  go(() => (n as dynamic)('dynamic')); // expect: dynamic
  go(() => (A() as dynamic).g); // expect: g
  go(() => (A() as dynamic)[1]); // expect: []
  go(() => (1 as dynamic) is Never); // expect: false
  go(() => (1 as dynamic) as Never); // expect: type 'int' is not a subtype of type 'Never' in type cast
  go(() => null as Never); // expect: type 'Null' is not a subtype of type 'Never' in type cast
  go(() => <Never>[] is List<int>); // expect: true
  go(() => <int>[] is List<Never>); // expect: false
  go(() => <String, Never>{}.runtimeType); // expect: _Map<String, Never>
  go(() => Never); // expect: Never
  go(() => (<Never>[] as List<Object>)..add(1)); // expect: type 'int' is not a subtype of type 'Never' of 'value'
  try {
    await stream().toList();
  } catch (e) {
    print(e);
  }
  // expect: stream
  try {
    print(await n('await'));
  } catch (e) {
    print(e);
  }
  // expect: await
  print(await Future<Never>.error('e').catchError((e) => n('$e!')).then(
    (x) => x,
    onError: (Object e) => e,
  )); // expect: e!
}
