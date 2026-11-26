int top(int x) => x;

extension FX on int Function(int) {
  int twice(int x) => this(this(x));
}

void main() {
  int Function(int) f = top;
  int Function(int)? g = top;
  Function h = top;
  print(
    f.toString(),
  ); // expect: Closure: (int) => int from Function 'top': static.
  print(f.hashCode == top.hashCode); // expect: true
  print(f.runtimeType); // expect: (int) => int
  print(
    g?.toString(),
  ); // expect: Closure: (int) => int from Function 'top': static.
  print(
    h.toString(),
  ); // expect: Closure: (int) => int from Function 'top': static.
  print(f.twice(2)); // expect: 2
  print(g?.hashCode == f.hashCode); // expect: true
  print((1, 2).toString()); // expect: (1, 2)
  print((1, 2).hashCode == (1, 2).hashCode); // expect: true
  (int, int)? r = (1, 2);
  print(r?.toString()); // expect: (1, 2)
  print(r.runtimeType); // expect: (int, int)
  print(r.toString()); // expect: (1, 2)
  final t = f.toString;
  print(t()); // expect: Closure: (int) => int from Function 'top': static.
  final u = (1, a: 2).toString;
  print(u()); // expect: (1, a: 2)
  print(null.toString()); // expect: null
  int? n;
  print(n.toString()); // expect: null
  print(n.hashCode == null.hashCode); // expect: true
  final nt = n.toString;
  print(nt()); // expect: null
  more();
  // expect: null
  // expect: 1
  // expect: true
  // expect: null
  // expect: 2
  // expect: nullNull
  // expect: aString
  // expect: null
  // expect: null
  // expect: null
  // expect: true
  // expect: (Invocation) => dynamic
  // expect: (Invocation) => dynamic
  // expect: true
  Object o = f;
  print(
    o.toString(),
  ); // expect: Closure: (int) => int from Function 'top': static.
  try {
    (f as dynamic).foo();
  } on NoSuchMethodError catch (e) {
    print('nsm');
  }
  // expect: nsm
  print(
    f.call.toString(),
  ); // expect: Closure: (int) => int from Function 'top': static.
  print([1].toString().length.toString().hashCode == 1); // expect: false
}

extension OnN on Object? {
  String s() => toString();
  int h() => this.hashCode;
  String Function() t() => toString;
  String u() {
    return '${this}$runtimeType';
  }
}

void more() {
  print(null.s());
  print(1.s());
  print(null.h() == null.hashCode);
  print(null.t()());
  print(2.t()());
  print(null.u());
  print('a'.u());
  int? x;
  print(x.s());
  Object? y;
  print((y.toString)());
  dynamic z;
  print((z.toString)());
  print(z.hashCode == null.hashCode);
  print((z.noSuchMethod).runtimeType);
  print(y.noSuchMethod.runtimeType);
  print(y.toString == y.toString);
}
