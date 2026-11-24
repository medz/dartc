import 'support.dart';

void main() {
  agrees('fields, equality and text', r'''
(int, String) pair(int n) => (n, 'n$n');
({int x, double y}) named() => (y: 2.5, x: 1);
(int, {String name, bool ok}) both = (4, ok: true, name: 'b');
(T, T) swap<T>((T, T) p) => (p.$2, p.$1);
int trace(int n) { print('t$n'); return n; }
const constant = (1, 'a', z: [2]);
void main() {
  final p = pair(3);
  print(p.$1); print(p.$2); print(p); print(named()); print(named().x); print(both.name);
  print(both); print(swap((1, 2))); print(swap(('a', 'b')).$1);
  print(p == (3, 'n3')); print(p == pair(4)); print(p.hashCode == (3, 'n3').hashCode);
  print((a: 1, b: 2) == (b: 2, a: 1)); print((1, 2) == (a: 1, b: 2)); Object o = (1, 2); print(o == (1, 2, 3));
  print((trace(1), b: trace(2), a: trace(3))); print((1,)); print(()); print((null, (2, 3)));
  print(constant); print(constant.z.first); print(constant == (1, 'a', z: const [2]));
  final map = {(1, 2): 'x', (a: 1): 'y'}; print(map[(1, 2)]); print(map[(a: 1)]);
  (num, Object?) wide = (1, null); print(wide.$1); print(wide.runtimeType);
  var r = (1, 2.5); r = (2, 3.5); print(r.$1 + r.$2);
  final list = [(1, 'a'), (2, 'b')]; print(list); print(list.runtimeType);
  for (final e in list) print(e.$1 * 2);
  print(['a', 'b'].indexed.toList());
}
''');

  agrees('types', r'''
Type typeOf<T>() => T;
bool fits<T>(Object? o) => o is T;
typedef Pair<A, B> = (A, B);
class Holder<T> { final (T, {T? other}) value; Holder(this.value); bool test(Object o) => o is (T, {T? other}); }
void take((int, int) p) => print(p.$1 + p.$2);
void main() {
  Object o = (1, 'a');
  print(o is (int, String)); print(o is (num, Object)); print(o is (int, int)); print(o is (int, String, int));
  print(o is ({int a})); print(o is Record); print(1 is Record); print(o.runtimeType);
  print((1, a: 2.5, b: null).runtimeType); print((1,).runtimeType); print(().runtimeType);
  print(typeOf<(int, {String s})>()); print(typeOf<Pair<int, bool>>()); print(typeOf<(int,)?>());
  print(fits<(int, int)>((1, 2))); print(fits<(int, int)>((1, 2.5))); print(fits<Record>((1, 2)));
  print(fits<({num a})>((a: 1))); print(fits<({num a})>((b: 1)));
  print(o as (int, String));
  try { o as (String, int); } catch (e) { print(e); }
  final h = Holder((1, other: 2)); print(h.test((1, other: null))); print(h.test(('a', other: null))); print(h.value);
  dynamic d = (1, name: 'x', f: (int n) => n + 1);
  print(d.$1); print(d.name); print(d.f(4));
  try { d.$2; } catch (e) { print('$e'.split('\n').first); }
  try { take(d); } catch (e) { print('$e'.split(' of')[0].length > 10); }
  void Function((int, int)) t = take; t((3, 4)); dynamic dt = t; dt((5, 6));
  print(<(int, int)>[].runtimeType); print(<(int, {String s}), int>{}.runtimeType);
  List<Object> os = <(int, int)>[]; print(os is List<(num, num)>); print(os is List<Record>); print(os is List<(int, String)>);
  (int, int)? none; print(none?.$1); none ??= (7, 8); print(none.$2);
  Record rec = (1, 2); print(rec); print(rec.hashCode == (1, 2).hashCode); print(identical(const (1, 2), const (1, 2)));
  print(((int, String) p) => 1);
}
''');
}
