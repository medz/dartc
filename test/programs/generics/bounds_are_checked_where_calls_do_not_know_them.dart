class A<T> {
  void m<S extends T>() => print(S);
  void n<S extends List<T>>(S a) => print(S);
}

class B {
  void m<T extends Comparable<T>, S extends List<T>>() => print((T, S));
}

void g<T extends num, S extends List<T>>([Object? a]) => print((T, S, a));
void main() {
  A<num> a = A<int>();
  try {
    a.m<double>();
  } catch (e) {
    print(e);
  }
  // expect: type 'double' is not a subtype of type 'int' of 'S'
  try {
    a.m<int>();
  } catch (e) {
    print(e);
  }
  // expect: int
  try {
    a.n<List<double>>([]);
  } catch (e) {
    print(e);
  }
  // expect: type 'List<double>' is not a subtype of type 'List<int>' of 'S'
  dynamic f = g;
  try {
    f<int, List<int>>();
  } catch (e) {
    print(e);
  }
  // expect: (int, List<int>, null)
  try {
    f<String, List<String>>();
  } catch (e) {
    print(e);
  }
  // expect: type 'String' is not a subtype of type 'num' of 'T'
  try {
    f<int, List<double>>();
  } catch (e) {
    print(e);
  }
  // expect: type 'List<double>' is not a subtype of type 'List<int>' of 'S'
  dynamic b = B();
  try {
    b.m<int, List<int>>();
  } catch (e) {
    print(e);
  }
  // expect: type 'int' is not a subtype of type 'Comparable<int>' of 'T'
  try {
    b.m<num, List<num>>();
  } catch (e) {
    print(e);
  }
  // expect: (num, List<num>)
  Function h = g;
  try {
    Function.apply(h, [1]);
  } catch (e) {
    print(e);
  }
  // expect: (num, List<num>, 1)
  try {
    h<String, List<String>>(2);
  } catch (e) {
    print(e);
  }
  // expect: type 'String' is not a subtype of type 'num' of 'T'
  dynamic t = (a as dynamic).m;
  try {
    t<double>();
  } catch (e) {
    print(e);
  }
  // expect: type 'double' is not a subtype of type 'int' of 'S'
  dynamic c = <T extends num>(T x) => print((T, x));
  try {
    c<String>('a');
  } catch (e) {
    print(e);
  }
  // expect: type 'String' is not a subtype of type 'num' of 'T'
  try {
    c('a');
  } catch (e) {
    print(e);
  }
  // expect: type 'String' is not a subtype of type 'num' of 'x'
  c(1); // expect: (num, 1)
  part();
  // expect: (int, 1, null, 5)
  // expect: (int, 1, 2, 5)
  // expect: (int, 1, 2, 3)
  // expect: (int, 1, null, 5)
  // expect: (int, 1, 2, 3)
  // expect: _TypeError
  // expect: (int, 1, null, 5)
  // expect: (int, 1, 2, 5)
  // expect: (int, 1, 2, 3)
  // expect: _TypeError
  // expect: NoSuchMethodError
  // expect: (int, 1, 2)
  // expect: _TypeError
  // expect: (int, 1, 7)
  // expect: (int, 1, null, 2)
  // expect: (dynamic, 1, null, 2)
  // expect: (num, 1, null, 5)
  // expect: Closure: (Object?) => int from Function 'compareTo':.
  // expect: true
  // expect: true
  // expect: -1
}

T opt<T extends num>(T a, [T? b, int c = 5]) {
  print((T, a, b, c));
  return a;
}

T nam<T>(T a, {T? b, int c = 5}) {
  print((T, a, b, c));
  return a;
}

void part() {
  int Function(int, [int?, int]) p = opt;
  dynamic q = p;
  Function f = p;
  p(1);
  p(1, 2);
  p(1, 2, 3);
  q(1);
  q(1, 2, 3);
  try {
    q('a');
  } catch (e) {
    print(e.runtimeType);
  }
  Function.apply(f, [1]);
  Function.apply(f, [1, 2]);
  Function.apply(f, [1, 2, 3]);
  try {
    Function.apply(f, ['a']);
  } catch (e) {
    print(e.runtimeType);
  }
  try {
    Function.apply(f, [1, 2, 3, 4]);
  } catch (e) {
    print(e.runtimeType);
  }
  String g<S>(S a, {S? b}) {
    print((S, a, b));
    return '$a';
  }

  final h = g<int>;
  Function.apply(h, [1], {#b: 2});
  dynamic k = h;
  try {
    k(1, b: 'x');
  } catch (e) {
    print(e.runtimeType);
  }
  k(1, b: 7);
  int Function(int, {int? b, int c}) n = nam;
  Function.apply(n, [1], {#c: 2});
  Function.apply(nam, [1], {#c: 2});
  Function.apply(opt, [1]);
  print(1.compareTo);
  final z = 1.5.compareTo;
  print(z == 1.5.compareTo);
  print(identical(z, z));
  print(z(2));
}
