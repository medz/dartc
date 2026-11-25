int calls = 0;
int next() => ++calls;
List<int>? none() => null;
void main() {
  final l = [1, 2, 3];
  bool yes = l.length > 2;
  int? nothing = l.isEmpty ? 1 : null;
  print([0, ...l, 4]); // expect: [0, 1, 2, 3, 4]
  print([...?none(), ...?l]); // expect: [1, 2, 3]
  print([if (yes) 'a' else 'b', if (!yes) 'c']); // expect: [a]
  print([for (var i = 0; i < 3; i++) i * i]); // expect: [0, 1, 4]
  print([
    for (final x in l)
      if (x.isOdd) ...[x, -x],
  ]); // expect: [1, -1, 3, -3]
  print([?nothing, ?l.first]); // expect: [1]
  print({...l, 9, if (yes) 10}); // expect: {1, 2, 3, 9, 10}
  print({
    for (final x in l) x: '$x!',
    ...{'a': 'b'},
    if (yes) 'y': 'n',
  }); // expect: {1: 1!, 2: 2!, 3: 3!, a: b, y: n}
  print({'a': ?nothing, ?nothing: 1, 'b': 2}); // expect: {b: 2}
  print(<num>[1, 2.5, ...l]); // expect: [1, 2.5, 1, 2, 3]
  dynamic d = [1, 2];
  print(<int>[...d]); // expect: [1, 2]
  try {
    d = ['x'];
    print(<int>[...d]);
  } catch (e) {
    print(e);
  }
  // expect: type 'String' is not a subtype of type 'int'
  print([
    next(),
    [next(), next()],
    {next(): next()},
  ]); // expect: [1, [2, 3], {4: 5}]
  print([
    for (var i = 0, j = 5; i < j; i++, j--) '$i$j',
  ]); // expect: [05, 14, 23]
  final fs = [for (var i = 0; i < 3; i++) () => i];
  print([for (final f in fs) f()]); // expect: [0, 1, 2]
  print(<int>[]); // expect: []
  print(<String, int>{}); // expect: {}
  print(<int>{}); // expect: {}
  print(const [
    1,
    [
      2,
      ['a'],
    ],
    null,
    2.5,
    true,
    {
      'k': {1},
    },
  ]); // expect: [1, [2, [a]], null, 2.5, true, {k: {1}}]
  var s = 0;
  int x;
  for (x in l) {
    s += x;
  }
  print(
    '$s ${[...l, ...l.map((e) => e * s)]}',
  ); // expect: 6 [1, 2, 3, 6, 12, 18]
  outer:
  for (final a in l) {
    for (final b in l) {
      if (b == 2) continue outer;
      if (a == 3) break outer;
      print('$a$b');
    }
  }
  // expect: 11
  // expect: 21
  for (final num v in d is List<num> ? <num>[] : [1]) {
    print(v);
  }
  // expect: 1
}
