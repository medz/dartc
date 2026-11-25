Type typeOf<T>() => T;
bool fits<T>(Object? o) => o is T;
typedef Pair<A, B> = (A, B);

class Holder<T> {
  final (T, {T? other}) value;
  Holder(this.value);
  bool test(Object o) => o is (T, {T? other});
}

void take((int, int) p) => print(p.$1 + p.$2);
void main() {
  Object o = (1, 'a');
  print(o is (int, String)); // expect: true
  print(o is (num, Object)); // expect: true
  print(o is (int, int)); // expect: false
  print(o is (int, String, int)); // expect: false
  print(o is ({int a})); // expect: false
  print(o is Record); // expect: true
  print(1 is Record); // expect: false
  print(o.runtimeType); // expect: (int, String)
  print((1, a: 2.5, b: null).runtimeType); // expect: (int, {double a, Null b})
  print((1,).runtimeType); // expect: (int)
  print(().runtimeType); // expect: ()
  print(typeOf<(int, {String s})>()); // expect: (int, {String s})
  print(typeOf<Pair<int, bool>>()); // expect: (int, bool)
  print(typeOf<(int,)?>()); // expect: (int)?
  print(fits<(int, int)>((1, 2))); // expect: true
  print(fits<(int, int)>((1, 2.5))); // expect: false
  print(fits<Record>((1, 2))); // expect: true
  print(fits<({num a})>((a: 1))); // expect: true
  print(fits<({num a})>((b: 1))); // expect: false
  print(o as (int, String)); // expect: (1, a)
  try {
    o as (String, int);
  } catch (e) {
    print(e);
  }
  // expect: type '(int, String)' is not a subtype of type '(String, int)' in type cast
  final h = Holder((1, other: 2));
  print(h.test((1, other: null))); // expect: true
  print(h.test(('a', other: null))); // expect: false
  print(h.value); // expect: (1, other: 2)
  dynamic d = (1, name: 'x', f: (int n) => n + 1);
  print(d.$1); // expect: 1
  print(d.name); // expect: x
  print(d.f(4)); // expect: 5
  try {
    d.$2;
  } catch (e) {
    print('$e'.split('\n').first);
  }
  // expect: NoSuchMethodError: Class '(int, {(int) => int f, String name})' has no instance getter '$2'.
  try {
    take(d);
  } catch (e) {
    print('$e'.split(' of')[0].length > 10);
  }
  // expect: true
  void Function((int, int)) t = take;
  t((3, 4)); // expect: 7
  dynamic dt = t;
  dt((5, 6)); // expect: 11
  print(<(int, int)>[].runtimeType); // expect: List<(int, int)>
  print(
    <(int, {String s}), int>{}.runtimeType,
  ); // expect: _Map<(int, {String s}), int>
  List<Object> os = <(int, int)>[];
  print(os is List<(num, num)>); // expect: true
  print(os is List<Record>); // expect: true
  print(os is List<(int, String)>); // expect: false
  (int, int)? none;
  print(none?.$1); // expect: null
  none ??= (7, 8);
  print(none.$2); // expect: 8
  Record rec = (1, 2);
  print(rec); // expect: (1, 2)
  print(rec.hashCode == (1, 2).hashCode); // expect: true
  print(identical(const (1, 2), const (1, 2))); // expect: true
  print(((int, String) p) => 1); // expect: Closure: ((int, String)) => int
}
