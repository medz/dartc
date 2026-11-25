typedef Narrow = int Function<T>();
typedef Wider = num Function<T>();
typedef One = Object? Function<T>(int a);
typedef Two = Object? Function<A, B>(A a);
int wide<T>({int? extra}) => extra ?? 0;
String both<T>(num a, {String? s, T? t}) => '$T $a $s $t';
String two<A, B>(A a, [B? b, int c = 1]) => '$A $B $a $b $c';

class C {
  final int n;
  C(this.n);
  String m<T>(int a, {T? t, int k = 2}) => '$T $a $t $k $n';
  static int s<T>([int k = 3]) => k;
}

class D extends C {
  D(super.n);
  String m<T>(num a, {T? t, int k = 3, String? more}) =>
      'D $T $a $t $k $n $more';
}

Object bind(Narrow f) => f<int>;
Object bindWider(Wider f) => f<int>;
Object one(One f) => f<int>;
Object bindTwo(Two f) => f<int, String>;
void go(Object? Function() f) {
  try {
    print(f());
  } on NoSuchMethodError {
    print('N');
  } catch (e) {
    print(e);
  }
}

void main() {
  final p = bind(wide);
  print(p is int Function({int? extra})); // expect: true
  if (p is int Function({int? extra})) {
    go(() => p(extra: 7));
    go(() => p());
    go(() => p(extra: null));
  }
  // expect: 7
  // expect: 0
  // expect: 0
  dynamic d = p;
  go(() => d(extra: 7)); // expect: 7
  go(() => d()); // expect: 0
  go(() => d.call(extra: 8)); // expect: 8
  go(
    () => d(extra: 'x'),
  ); // expect: type 'String' is not a subtype of type 'int?' of 'extra'
  go(() => Function.apply(d, [], {#extra: 9})); // expect: 9
  go(() => Function.apply(d, [])); // expect: 0
  final q = one(both);
  if (q is Object? Function(num, {String? s, int? t})) {
    go(() => q(1.5, s: 'a', t: 3));
    go(() => q(1, t: 3));
  }
  // expect: int 1.5 a 3
  // expect: int 1 null 3
  if (q is Object? Function(int, {String? s}))
    go(() => q(5, s: 'only')); // expect: int 5 only null
  go(() => (q as dynamic)(2.5, s: 'b')); // expect: int 2.5 b null
  go(
    () => (q as dynamic)(2.5, t: 'b'),
  ); // expect: type 'String' is not a subtype of type 'int?' of 't'
  go(
    () => Function.apply(q as Function, [2], {#t: 4, #s: 'c'}),
  ); // expect: int 2 c 4
  final r = bindTwo(two);
  if (r is Object? Function(int, [String?, int])) {
    go(() => r(1, 'b', 3));
    go(() => r(1, 'b'));
    go(() => r(1));
  }
  // expect: int String 1 b 3
  // expect: int String 1 b 1
  // expect: int String 1 null 1
  go(() => (r as dynamic)(1, 'x', 9)); // expect: int String 1 x 9
  go(() => Function.apply(r as Function, [1, 'y'])); // expect: int String 1 y 1
  for (final c in [C(4), D(5)]) {
    final s = one(c.m);
    print(s is Object? Function(int, {int? t, int k}));
    print(s is Object? Function(num, {String? more}));
    if (s is Object? Function(int, {int? t, int k})) go(() => s(1, t: 2, k: 8));
    if (s is Object? Function(num, {String? more})) go(() => s(1.5, more: 'z'));
    go(() => (s as dynamic)(1, t: 6));
    go(() => (s as dynamic)(1, t: 'bad'));
  }
  // expect: true
  // expect: false
  // expect: int 1 2 8 4
  // expect: int 1 6 2 4
  // expect: type 'String' is not a subtype of type 'int?' of 't'
  // expect: true
  // expect: true
  // expect: D int 1 2 8 5 null
  // expect: D int 1.5 null 3 5 z
  // expect: D int 1 6 3 5 null
  // expect: type 'String' is not a subtype of type 'int?' of 't'
  final u = bind(C.s);
  if (u is int Function(int)) go(() => u(12)); // expect: 12
  final local = <T>(int a, {T? t}) => '$T $a $t ${p == d}';
  final t = one(local);
  if (t is Object? Function(int, {int? t}))
    go(() => t(1, t: 2)); // expect: int 1 2 true
  go(() => (t as dynamic)(1, t: 3)); // expect: int 1 3 true
  // What does not fit.
  go(() => d(1)); // expect: N
  go(() => d(other: 1)); // expect: N
  go(() => d<int>()); // expect: N
  go(() => d.call(1)); // expect: N
  go(() => (q as dynamic)()); // expect: N
  go(() => (q as dynamic)(1, u: 2)); // expect: N
  go(() => Function.apply(d, [1])); // expect: N
  go(() => Function.apply(d, [], {#other: 1})); // expect: N
  go(() => (r as dynamic)()); // expect: N
  go(
    () => (r as dynamic)(1, 2),
  ); // expect: type 'int' is not a subtype of type 'String?' of 'b'
  // How the type is written where they get their arguments does not matter.
  print((
    bind(wide) == bind(wide),
    bind(wide) == bindWider(wide),
    bind(wide).hashCode == bindWider(wide).hashCode,
  )); // expect: (true, true, true)
  print((
    {bind(wide): 1}[bindWider(wide)],
    bind(wide) == bind(C.s),
  )); // expect: (1, false)
}
