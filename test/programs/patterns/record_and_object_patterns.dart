class Point {
  final int x, y;
  Point(this.x, this.y);
  int get sum => x + y;
  int plus(int n) => x + n;
}

class Box<T> {
  final T value;
  Box(this.value);
}

sealed class Shape {}

class Square extends Shape {
  final double side;
  Square(this.side);
}

class Circle extends Shape {
  final double r;
  Circle(this.r);
}

double area(Shape s) => switch (s) {
  Square(:final side) => side * side,
  Circle(r: var radius) => radius * 3,
};
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
  print(area(Square(2))); // expect: 4.0
  print(area(Circle(1))); // expect: 3.0
  for (final o in <Object?>[
    (1, 2),
    (1, name: 'n'),
    (a: 1, b: 2),
    (),
    Point(0, 0),
    Point(0, 9),
    Point(0, 3),
    Point(5, 8),
    Point(1, 1),
    Box(4),
    Box('s'),
    Box<String?>(null),
    Box(2.5),
    4,
    -4,
    3,
    'abc',
    'ab',
    [7, 8],
    <int>[],
    null,
    ('a', 'b'),
  ])
    print(what(o));
  // expect: ints 3
  // expect: named 1 n
  // expect: b is 2
  // expect: empty
  // expect: origin
  // expect: high 9
  // expect: plus 100
  // expect: big 5 13
  // expect: plus 101
  // expect: int box 4
  // expect: string box s
  // expect: no box
  // expect: other box 2.5
  // expect: even 4
  // expect: other
  // expect: other
  // expect: long 3
  // expect: other
  // expect: list of 7
  // expect: other
  // expect: null
  // expect: other
  var (a, b) = (1, 'x');
  print('$a $b'); // expect: 1 x
  final (:x, y: (p, q)) = (x: 1, y: (2, 3));
  print(x + p + q); // expect: 6
  final Point(x: px, :sum) = Point(3, 4);
  print(px * sum); // expect: 21
  (a, b) = (5, 'y');
  print('$a $b'); // expect: 5 y
  var i = 1, j = 2;
  (i, j) = (j, i);
  print('$i $j'); // expect: 2 1
  print((i, j) = (8, 9)); // expect: (8, 9)
  print(i); // expect: 8
  final list = [1, 2];
  (list[0] == 1 ? null : i);
  if ((1, Point(2, 3)) case (final n, Point(x: 2, y: final m)) when n < m)
    print('if $n $m'); // expect: if 1 3
  if (Object() case int _)
    print('no');
  else
    print('else'); // expect: else
  for (final (k, v) in [(1, 'a'), (2, 'b')]) print('$k$v');
  // expect: 1a
  // expect: 2b
  for (var (k, v) = (0, 1); k < 20; (k, v) = (v, k + v)) print(k);
  // expect: 0
  // expect: 1
  // expect: 1
  // expect: 2
  // expect: 3
  // expect: 5
  // expect: 8
  // expect: 13
  final fs = [
    for (var (k, v) = (0, 1); k < 3; (k, v) = (k + 1, v * 2)) () => '$k $v',
  ];
  for (final f in fs) print(f());
  // expect: 0 1
  // expect: 1 2
  // expect: 2 4
  for (final MapEntry(:key, :value) in {'q': 1}.entries) print('$key=$value');
  // expect: q=1
  final doubled = [
    for (final (n, _) in [(1, 2), (3, 4)]) n * 2,
    if (a case 5) 'five' else 'no',
  ];
  print(doubled); // expect: [2, 6, five]
  dynamic d = (3, 4);
  final (dynamic s, t) = d as (Object, Object);
  print(s + (t as int)); // expect: 7
}
