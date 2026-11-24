import 'support.dart';

void main() {
  agrees('record and object patterns', r'''
class Point { final int x, y; Point(this.x, this.y); int get sum => x + y; int plus(int n) => x + n; }
class Box<T> { final T value; Box(this.value); }
sealed class Shape {}
class Square extends Shape { final double side; Square(this.side); }
class Circle extends Shape { final double r; Circle(this.r); }
double area(Shape s) => switch (s) { Square(:final side) => side * side, Circle(r: var radius) => radius * 3 };
String what(Object? o) => switch (o) {
  (int a, int b) => 'ints ${a + b}',
  (int a, name: String n) => 'named $a $n',
  (a: _, b: var b) => 'b is $b',
  () => 'empty',
  Point(x: 0, y: 0) => 'origin',
  Point(x: 0, :var y) when y > 5 => 'high $y',
  Point(:final x, sum: > 10 && var s) => 'big $x $s',
  Point(plus: var p) => 'plus ${p(100)}',
  Box<int>(value: var v) => 'int box $v',
  Box(value: String v?) => 'string box $v',
  Box(value: null) => 'no box',
  Box(:var value) => 'other box $value',
  int(isEven: true, sign: 1) && var n => 'even $n',
  String(length: > 2 && var length) => 'long $length',
  List<int>(isEmpty: false, first: var f) => 'list of $f',
  null => 'null',
  _ => 'other',
};
void main() {
  print(area(Square(2))); print(area(Circle(1)));
  for (final o in <Object?>[(1, 2), (1, name: 'n'), (a: 1, b: 2), (), Point(0, 0), Point(0, 9), Point(0, 3), Point(5, 8), Point(1, 1),
      Box(4), Box('s'), Box<String?>(null), Box(2.5), 4, -4, 3, 'abc', 'ab', [7, 8], <int>[], null, ('a', 'b')]) print(what(o));
  var (a, b) = (1, 'x'); print('$a $b');
  final (:x, y: (p, q)) = (x: 1, y: (2, 3)); print(x + p + q);
  final Point(x: px, :sum) = Point(3, 4); print(px * sum);
  (a, b) = (5, 'y'); print('$a $b');
  var i = 1, j = 2; (i, j) = (j, i); print('$i $j');
  print((i, j) = (8, 9)); print(i);
  final list = [1, 2]; (list[0] == 1 ? null : i);
  if ((1, Point(2, 3)) case (final n, Point(x: 2, y: final m)) when n < m) print('if $n $m');
  if (Object() case int _) print('no'); else print('else');
  for (final (k, v) in [(1, 'a'), (2, 'b')]) print('$k$v');
  for (var (k, v) = (0, 1); k < 20; (k, v) = (v, k + v)) print(k);
  final fs = [for (var (k, v) = (0, 1); k < 3; (k, v) = (k + 1, v * 2)) () => '$k $v']; for (final f in fs) print(f());
  for (final MapEntry(:key, :value) in {'q': 1}.entries) print('$key=$value');
  final doubled = [for (final (n, _) in [(1, 2), (3, 4)]) n * 2, if (a case 5) 'five' else 'no']; print(doubled);
  dynamic d = (3, 4); final (dynamic s, t) = d as (Object, Object); print(s + (t as int));
}
''');

  agrees('list and map patterns', r'''
String what(Object? o) => switch (o) {
  [] => 'none',
  [int a] => 'one int $a',
  [var a, 'x', ...] => 'x second after $a',
  [var first, ..., var last] when first == last => 'same ends $first',
  [int a, int b, ...var rest] => 'ints $a $b $rest',
  [...var all, 9] => 'nine after $all',
  <String>[var a, ...var r, var z] => 'strings $a $r $z',
  List(length: > 3) => 'long',
  {'a': int n, 'b': var b} => 'a $n b $b',
  {'n': null} => 'null n',
  {'k': [1, var k]} => 'k $k',
  {1: var one} => 'one is $one',
  Map(isEmpty: true) => 'empty map',
  _ => 'other',
};
void main() {
  for (final o in <Object?>[[], [1], ['q'], [0, 'x', 3], [4, 5, 4], [1, 2, 3, 4], [1, 2], ['z', 8, 9], <String>['a', 'b', 'c'], [1.5, 2, 3, 4],
      {'a': 1, 'b': null}, {'a': 1}, {'n': null}, {'m': 1}, {'k': [1, 2]}, {1: 'i'}, {}, 5]) print(what(o));
  var [a, b, ...c] = [1, 2, 3, 4]; print('$a $b $c ${c.runtimeType}');
  [a, b] = [b, a]; print('$a $b');
  final {'x': x, 'y': y} = {'x': 1, 'y': 2.5}; print(x + y);
  try { final [q] = [1, 2]; print(q); } catch (e) { print(e.runtimeType); print(e); }
  try { final {'q': q} = {'x': 1}; print(q); } catch (e) { print(e.runtimeType); print(e); }
  final [[m, _], [n, _]] = [[1, 2], [3, 4]]; print(m + n);
  Map<String, int?> some = {'v': null}; if (some case {'v': final v}) print('v $v'); if (some case {'w': final w}) print('w $w'); else print('no w');
  for (final [p, q] in [[1, 2], [3, 4]]) print(p * q);
  switch ([1, 2]) { case [var h, ...] when h > 1: print('big'); case [1, var t]: print('t $t'); default: print('none'); }
  try { var [int z, ...] = <int>[]; print(z); } catch (e) { print(e); }
}
''');

  agrees('patterns that have to match', r'''
class A { int x = 1; }
void main() {
  void t(void Function() f) { try { f(); } catch (e) { print('${e.runtimeType}: $e'); } }
  dynamic d = [[1, 2], (3, 4)], i = 5, n = null;
  t(() { final [[m, _], (o, _)] = d; print(m + o); });
  t(() { final [int a, _] = d; print(a); });
  t(() { final (int a, _) = (i, i); print(a); });
  t(() { final (String a, _) = (i, i); print(a); });
  t(() { final (a, b) = i; print(a); });
  t(() { final A(:x) = i; print(x); });
  t(() { final A(:x) = n; print(x); });
  t(() { final {'a': x} = n; print(x); });
  t(() { String s; (s,) = (i,); print(s); });
  t(() { int s; (s,) = (i,); print(s); });
  t(() { final [String a] = [i]; print(a); });
  t(() { final [a!] = [n]; print(a); });
  t(() { final [a as String] = [i]; print(a); });
  t(() { for (final (int a, String b) in [(i, i)]) print(a); });
  t(() { var (a, [b]) = (1, <int>[]); print(b); });
  t(() { var [String z, ...] = [i]; print(z); });
  t(() { final (Object a, num b) = (i, n); print(b); });
  t(() { final [(int, int) r] = [i]; print(r); });
}
''');

  agrees('alternatives and shared bodies', r'''
String what(Object o) {
  switch (o) {
    case (int n, _) || (_, int n):
      return 'int $n';
    case [String s] || (String s) || {'s': String s}:
      final f = () => 's is $s';
      return f();
    case num n when n is int && n > 100:
    case num n when n is double && n > 2:
      return 'large $n';
    case 1 || 2 || 3:
      return 'small';
    case 4:
    case 5 when o == 5:
      return 'four or five';
    case bool():
    case Set _:
    default:
      return 'default';
  }
}
int own(int n) {
  switch (n) {
    case 1: var x = 1; while (x < 5) { x++; if (x == 4) break; } print(x);
    case 2: for (var x = 0; x < 2; x++) { print('b$x'); }
    case 3 when n > 1: { var y = n; y++; print(y); }
    default: var x = n; x += 2; return x;
  }
  final z = switch (n) { 1 => () { var x = 4; x++; return x; }(), var k when k > 2 => k + 1, var k => k * 5 };
  return z;
}
int jump(int n) {
  var steps = 0;
  switch (n) {
    first: case 1: steps += 1; continue third;
    case 2: steps += 10; continue first;
    third: case 3: steps += 100; if (steps < 300) continue third; break;
    case 4: steps += 1000; continue last;
    last: default: steps += 5;
  }
  return steps;
}
void main() {
  for (final o in <Object>[(1, 'a'), ('a', 2), ['q'], 'w', {'s': 'e'}, 101, 99, 3.5, 1.5, 2, 4, 5, true, {1}]) print(what(o));
  for (final n in [1, 2, 3, 4, 5]) print(jump(n));
  for (final n in [1, 2, 3, 4, 5]) print(own(n));
  var s = 0; outer: for (var i = 0; i < 5; i++) { switch (i) { case 1: continue outer; case 3: break outer; default: s += i; } } print(s);
  final x = switch ((1, 2)) { (var a, var b) when a > b => a, (var a, _) => a * 10 }; print(x);
  final Object v = 3; print(switch (v) { int n && >= 1 && <= 3 => 'range $n', int() || double() => 'number', _ => '?' });
  if (v case int n || (int n, _)) print(n);
  var caught = 0; final fs = []; for (final o in [(1, 2), (3, 4)]) { if (o case (var a, _) || (_, var a)) { fs.add(() => a += 1); fs.add(() => a); } } for (final f in fs) print(f());
  print(caught);
}
''');

  agrees('patterns evaluate getters once', r'''
class Noisy { final int n; Noisy(this.n); int get value { print('value'); return n; } Noisy get self { print('self'); return this; } }
class L { final List<int> l; L(this.l); int get length { print('length'); return l.length; } int operator [](int i) { print('[$i]'); return l[i]; } }
String what(Object o) => switch (o) {
  Noisy(value: 1) => 'one',
  Noisy(value: 2) => 'two',
  Noisy(self: Noisy(value: 3)) => 'three',
  Noisy(value: var v, self: Noisy(value: > 4)) => 'many $v',
  Noisy(value: var v) => 'some $v',
  _ => 'none',
};
void main() {
  for (final n in [1, 2, 3, 4, 5]) print(what(Noisy(n)));
  switch (Noisy(7)) { case Noisy(value: 6): print(6); case Noisy(value: 7) when Noisy(1).value == 2: print('when'); case Noisy(value: < 9 && var w): print(w); }
  if (Noisy(3) case Noisy(value: 2) || Noisy(value: 3)) print('yes');
}
''');
}
