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
  for (final o in <Object?>[
    [],
    [1],
    ['q'],
    [0, 'x', 3],
    [4, 5, 4],
    [1, 2, 3, 4],
    [1, 2],
    ['z', 8, 9],
    <String>['a', 'b', 'c'],
    [1.5, 2, 3, 4],
    {'a': 1, 'b': null},
    {'a': 1},
    {'n': null},
    {'m': 1},
    {
      'k': [1, 2],
    },
    {1: 'i'},
    {},
    5,
  ])
    print(what(o));
  // expect: none
  // expect: one int 1
  // expect: other
  // expect: x second after 0
  // expect: same ends 4
  // expect: ints 1 2 [3, 4]
  // expect: ints 1 2 []
  // expect: nine after [z, 8]
  // expect: strings a [b] c
  // expect: long
  // expect: a 1 b null
  // expect: other
  // expect: null n
  // expect: other
  // expect: k 2
  // expect: one is i
  // expect: empty map
  // expect: other
  var [a, b, ...c] = [1, 2, 3, 4];
  print('$a $b $c ${c.runtimeType}'); // expect: 1 2 [3, 4] List<int>
  [a, b] = [b, a];
  print('$a $b'); // expect: 2 1
  final {'x': x, 'y': y} = {'x': 1, 'y': 2.5};
  print(x + y); // expect: 3.5
  try {
    final [q] = [1, 2];
    print(q);
  } catch (e) {
    print(e.runtimeType);
    print(e);
  }
  // expect: StateError
  // expect: Bad state: Pattern matching error
  try {
    final {'q': q} = {'x': 1};
    print(q);
  } catch (e) {
    print(e.runtimeType);
    print(e);
  }
  // expect: StateError
  // expect: Bad state: Pattern matching error
  final [[m, _], [n, _]] = [
    [1, 2],
    [3, 4],
  ];
  print(m + n); // expect: 4
  Map<String, int?> some = {'v': null};
  if (some case {'v': final v}) print('v $v'); // expect: v null
  if (some case {'w': final w})
    print('w $w');
  else
    print('no w'); // expect: no w
  for (final [p, q] in [
    [1, 2],
    [3, 4],
  ])
    print(p * q);
  // expect: 2
  // expect: 12
  switch ([1, 2]) {
    case [var h, ...] when h > 1:
      print('big');
    case [1, var t]:
      print('t $t');
    default:
      print('none');
  }
  // expect: t 2
  try {
    var [int z, ...] = <int>[];
    print(z);
  } catch (e) {
    print(e);
  }
  // expect: Bad state: Pattern matching error
}
