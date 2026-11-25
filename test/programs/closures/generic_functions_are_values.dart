T id<T>(T t) => t;

class A {
  T m<T>(T t) => t;
  Type k<T>() => T;
  static S s<S>(S s) => s;
}

typedef F = T Function<T>(T);
void main() {
  F f = id;
  print(f<int>(1)); // expect: 1
  print(f('x')); // expect: x
  final g = A().m;
  print(g<int>(3)); // expect: 3
  int Function(int) h = A().m;
  print(h(4)); // expect: 4
  F k = A.s;
  print(k(2.5)); // expect: 2.5
  T local<T>(T t) => t;
  F l = local;
  print(l(true)); // expect: true
  print(f is F); // expect: true
  print(f.runtimeType); // expect: <Y0>(Y0) => Y0
  dynamic d = f;
  print(d<int>(1)); // expect: 1
  print(d(2)); // expect: 2
  var t = A().k;
  print(t<int>()); // expect: int
  print([id][0]('z')); // expect: z
  print(id == f); // expect: true
  final e = <T>(T x) => [x];
  print(e<num>(1)); // expect: [1]
  print(e('a').runtimeType); // expect: List<String>
  print(f); // expect: Closure: <Y0>(Y0) => Y0 from Function 'id': static.
}
