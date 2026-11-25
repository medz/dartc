import 'dart:async';

mixin Box<T> {
  late T item;
  Type get kind => T;
  T echo(T x) => item = x;
}

mixin class Nested<T> = Object with Box<T>;
mixin class Twice<T> = Object with Nested<List<T>>;
class Application<T>() with Twice<T>;

class Plain extends Nested<int> {}

abstract class Contract<T> {
  T value(T x, {int k = 3});
  R generic<R extends T>(R x);
  Future<R> later<R>(FutureOr<R> f(T x));
  set w(T x);
  T operator [](int i);
}

class Missing implements Contract<int> {
  dynamic noSuchMethod(Invocation i) {
    print((
      i.memberName == #later,
      i.positionalArguments.length,
      i.namedArguments.length,
      i.typeArguments,
    ));
    return i.isSetter
        ? null
        : i.memberName == #later
        ? Future<String>.value('x')
        : 5;
  }
}

class Child extends Missing {
  int a() => super.value(1);
  int b() {
    final f = super.value;
    return f(2, k: 9);
  }

  int c() => super.generic<int>(7);
  int d() => super[3];
  void e() {
    super.w = 8;
  }
}

class Wide implements Map<int, int> {
  dynamic noSuchMethod(i) => 0;
  int get length => 1;
}

class Other implements List<int> {
  dynamic noSuchMethod(i) => null;
  int get length => 2;
}

Stream<int> events(int count) async* {
  print('start');
  try {
    for (var i = 0; i < count; i++) {
      try {
        yield i;
      } finally {
        print('inner $i');
      }
    }
  } finally {
    print('outer');
  }
}

FutureOr<Iterable<int>> union() sync* {
  yield 1;
}

void main() async {
  final a = Application<String>();
  a.item = ['a'];
  print((
    a.item,
    a.kind,
    a.echo(['b']),
    a is Nested<List<String>>,
    a is Box<List<String>>,
    a is Twice<String>,
  )); // expect: ([a], List<String>, [b], true, true, true)
  final p = Plain()..item = 4;
  print((p.item, p.kind)); // expect: (4, int)
  final c = Child();
  print((c.a(), c.b(), c.c(), c.d()));
  // expect: (false, 1, 1, [])
  // expect: (false, 1, 1, [])
  // expect: (false, 1, 0, [int])
  // expect: (false, 1, 0, [])
  // expect: (5, 5, 5, 5)
  c.e(); // expect: (false, 1, 0, [])
  Contract<num> n = Missing();
  print(n.value(3));
  // expect: (false, 1, 1, [])
  // expect: 5
  try {
    n.value(1.5);
  } catch (e) {
    print(e);
  }
  // expect: type 'double' is not a subtype of type 'int' of 'x'
  try {
    n.w = 1.5;
  } catch (e) {
    print(e);
  }
  // expect: type 'double' is not a subtype of type 'int' of 'x'
  print(await n.later<String>((x) => 'y'));
  // expect: (true, 1, 0, [String])
  // expect: x
  dynamic d = n;
  print(await d.later<String>((int x) => 'y'));
  // expect: (true, 1, 0, [String])
  // expect: x
  try {
    d.value('x');
  } catch (e) {
    print(e);
  }
  // expect: type 'String' is not a subtype of type 'int' of 'x'
  final t = n.value;
  print(t(4));
  // expect: (false, 1, 1, [])
  // expect: 5
  print(t is int Function(int)); // expect: true
  try {
    (t as dynamic)('a');
  } catch (e) {
    print(e);
  }
  // expect: type 'String' is not a subtype of type 'int' of 'x'
  dynamic w = Wide();
  try {
    w.addAll({1: 2});
    w.addAll([1]);
  } catch (e) {
    print(e.runtimeType);
  }
  // expect: _TypeError
  print((w as Wide).length);
  // expect: 1
  // expect: start
  // expect: inner 0
  // expect: outer
  Other()
    ..addAll([1])
    ..add(2);
  final s = events(2).listen((v) => print('v $v'));
  await s.cancel();
  print('end'); // expect: end
  print((union() as Iterable<int>).toList()); // expect: [1]
}
