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
    case 1:
      var x = 1;
      while (x < 5) {
        x++;
        if (x == 4) break;
      }
      print(x);
    case 2:
      for (var x = 0; x < 2; x++) {
        print('b$x');
      }
    case 3 when n > 1:
      {
        var y = n;
        y++;
        print(y);
      }
    default:
      var x = n;
      x += 2;
      return x;
  }
  final z = switch (n) {
    1 => () {
      var x = 4;
      x++;
      return x;
    }(),
    var k when k > 2 => k + 1,
    var k => k * 5,
  };
  return z;
}

int jump(int n) {
  var steps = 0;
  switch (n) {
    first:
    case 1:
      steps += 1;
      continue third;
    case 2:
      steps += 10;
      continue first;
    third:
    case 3:
      steps += 100;
      if (steps < 300) continue third;
      break;
    case 4:
      steps += 1000;
      continue last;
    last:
    default:
      steps += 5;
  }
  return steps;
}

void main() {
  for (final o in <Object>[
    (1, 'a'),
    ('a', 2),
    ['q'],
    'w',
    {'s': 'e'},
    101,
    99,
    3.5,
    1.5,
    2,
    4,
    5,
    true,
    {1},
  ])
    print(what(o));
  // expect: int 1
  // expect: int 2
  // expect: s is q
  // expect: s is w
  // expect: s is e
  // expect: large 101
  // expect: default
  // expect: large 3.5
  // expect: default
  // expect: small
  // expect: four or five
  // expect: four or five
  // expect: default
  // expect: default
  for (final n in [1, 2, 3, 4, 5]) print(jump(n));
  // expect: 301
  // expect: 311
  // expect: 300
  // expect: 1005
  // expect: 5
  for (final n in [1, 2, 3, 4, 5]) print(own(n));
  // expect: 4
  // expect: 5
  // expect: b0
  // expect: b1
  // expect: 10
  // expect: 4
  // expect: 4
  // expect: 6
  // expect: 7
  var s = 0;
  outer:
  for (var i = 0; i < 5; i++) {
    switch (i) {
      case 1:
        continue outer;
      case 3:
        break outer;
      default:
        s += i;
    }
  }
  print(s); // expect: 2
  final x = switch ((1, 2)) {
    (var a, var b) when a > b => a,
    (var a, _) => a * 10,
  };
  print(x); // expect: 10
  final Object v = 3;
  print(switch (v) {
    int n && >= 1 && <= 3 => 'range $n',
    int() || double() => 'number',
    _ => '?',
  }); // expect: range 3
  if (v case int n || (int n, _)) print(n); // expect: 3
  var caught = 0;
  final fs = [];
  for (final o in [(1, 2), (3, 4)]) {
    if (o case (var a, _) || (_, var a)) {
      fs.add(() => a += 1);
      fs.add(() => a);
    }
  }
  for (final f in fs) print(f());
  // expect: 2
  // expect: 2
  // expect: 4
  // expect: 4
  print(caught); // expect: 0
}
