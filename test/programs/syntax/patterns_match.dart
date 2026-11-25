String g(int n) => switch (n) {
  < 0 => 'neg',
  0 || 1 => 'small',
  >= 10 && < 20 => 'teen',
  int x => 'other $x',
};
void main() {
  int? a = 5;
  if (a case final x?) print(x); // expect: 5
  a = null;
  if (a case final x?) {
    print(x);
  } else {
    print('null');
  }
  // expect: null
  Object o = 'text';
  if (o case String s when s.length > 2) print(s); // expect: text
  if (o case int n)
    print(n);
  else
    print('no'); // expect: no
  for (final n in [-1, 0, 1, 15, 30]) print(g(n));
  // expect: neg
  // expect: small
  // expect: small
  // expect: teen
  // expect: other 30
  var t = 0;
  if (3 case var q when (t = q) > 2) t++;
  print(t); // expect: 4
  switch (o) {
    case String s when s.isEmpty:
      print('e');
    case String _:
      print("s");
    default:
      print('d');
  }
  // expect: s
  switch (7) {
    case > 5:
      print('big');
    case 3:
      print('three');
  }
  // expect: big
  final fs = <int Function()>[];
  for (var i = 0; i < 3; i++) {
    if (i case var k when k != 1) fs.add(() => k * 10);
  }
  print(fs.map((f) => f()).toList()); // expect: [0, 20]
  print(switch (o) {
    'a' => 1,
    'text' => 2,
    _ => 3,
  }); // expect: 2
  switch ('b') {
    case 'a':
    case 'b':
      print('ab');
    case _:
      print('x');
  }
  // expect: ab
}
