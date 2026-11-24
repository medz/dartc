import 'support.dart';

void main() {
  agrees('values', r'''
Iterable<int> count(int n) sync* { print('start'); for (var i = 0; i < n; i++) { yield i; } print('end'); }
Iterable<int> down(int n) sync* { while (n > 0) yield n--; }
Iterable<T> twice<T>(Iterable<T> all) sync* { for (final e in all) { yield e; yield e; } }
Iterable<int> tree(int depth) sync* { if (depth == 0) return; yield* tree(depth - 1); yield depth; yield* tree(depth - 1); }
Iterable<Object?> mixed() sync* { yield 1; yield* [2, 'a']; yield null; yield* const {}.keys; yield 2.5; }
class Node { final int v; final List<Node> kids; Node(this.v, [this.kids = const []]); Iterable<int> get all sync* { yield v; for (final k in kids) yield* k.all; } Iterable<int> operator ~() sync* { yield -v; } }
Iterable<int> fib() sync* { var (a, b) = (0, 1); while (true) { yield a; (a, b) = (b, a + b); } }
main() {
  print(count(3).toList()); final it = count(2); print(it.first); print(it.length);
  final d = down(3); print(d.toList()); print(d.toList()); print(twice(['a', 'b']).toList()); print(twice([1]).runtimeType.toString().contains('int'));
  print(tree(3).join(',')); print(mixed().toList()); print(Node(1, [Node(2), Node(3, [Node(4)])]).all.toList()); print((~Node(5)).toList()); print(fib().skip(5).take(5).toList());
  final i = count(1).iterator; print(i.moveNext()); print(i.current); print(i.moveNext()); print(i.moveNext());
  Iterable<int> local(int k) sync* { void add() => k += 10; yield k; add(); yield k; }
  final l = local(1); print(l.toList()); print(l.toList()); var outer = 0; final c = () sync* { outer++; yield outer; }; print(c().toList()); final o = c(); print(o.toList()); print(o.toList());
  print([for (final x in fib().take(4)) x * 2]); for (final (a, b) in fib().indexed.take(3)) print('$a$b'); Iterable<num> n = count(1); print(n is Iterable<int>); dynamic dy = count; print(dy(2).last);
}
''');

  agrees('exceptions and exits', r'''
Iterable<int> f(int n) sync* {
  try { yield 1; if (n == 1) throw 'one'; if (n == 2) return; yield 2; } on String catch (e) { print('caught $e'); yield 10; } finally { print('finally $n'); yield 100; }
  yield 3;
}
Iterable<int> g() sync* { yield 1; throw StateError('bad'); }
Iterable<int> h() sync* { try { yield* g(); } catch (e) { print('h $e'); yield 7; } }
Iterable<int> nested() sync* { outer: for (var i = 0; i < 4; i++) { try { for (var j = 0; j < 3; j++) { try { if (i == 1) continue outer; if (i == 2 && j == 1) break outer; yield i * 10 + j; } finally { print('in $i$j'); } } } finally { print('out $i'); yield -i; } } }
Iterable<int> sw(Object o) sync* { switch (o) { case int n when n > 1: yield n; case (int a, int b): yield a; yield b; case [var x, ...]: yield 9; default: yield 0; } }
Iterable<String> catches() sync* { for (var i = 0; i < 3; i++) { try { if (i == 1) throw i; yield 'ok $i'; } catch (e, s) { yield 'e$e'; try { rethrow; } catch (e2) { yield 'again $e2'; } } } }
Iterable<int> bad(Iterable<int>? other) sync* { yield* other!; }
main() {
  for (var n = 0; n < 3; n++) print(f(n).toList());
  try { print(g().toList()); } catch (e) { print(e); } final i = g().iterator; print(i.moveNext()); try { i.moveNext(); } catch (e) { print(e); } print(i.moveNext());
  print(h().toList()); print(nested().toList()); print(sw(5).toList()); print(sw((1, 2)).toList()); print(sw([1]).toList()); print(sw('x').toList()); print(catches().toList());
  try { bad(null).toList(); } catch (e) { print(e); } for (final x in f(0)) { print(x); if (x == 2) break; }
  late final late1 = f(0).length; print(late1); double total = 0; Iterable<double> ds(bool b) sync* { double x = 0.5; bool flag = b; for (var i = 0; i < 3; i++) { x *= 2; if (flag) yield x; flag = !flag; } } for (final x in ds(true)) total += x; print(total);
}
''');

  agrees('loops over nothing', r'''
      Stream<Never> s() async* { throw 's';
              } Stream<Never> e() async* {} void main() async { try { await for (final x in s()) { print(x);
              } } catch (e) { print(e);
              } await for (final x in e()) { print('no');
              } await for (Never _ in e()) {} for (final x in <Never>[]) { print(x);
              } for (Never x in const <Never>[]) { print('z');
              } print([for (final x in <Never>[]) x]);
              print([await for (final x in e()) x]);
              l: for (final x in <Never>[]) { continue l;
              } for (final Never x in <Never>[]) { break;
              } int k = 0;
              for (k in <Never>[]) {} print(k);
              outer: await for (final x in e()) { break outer;
              } print('end');
              }
  ''');
}
