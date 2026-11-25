void main() {
  final fs = <int Function()>[];
  for (final x in [1, 2, 3]) {
    fs.add(() => x);
  }
  for (var y in [4, 5]) {
    y++;
    fs.add(() => y++);
  }
  print(fs.map((f) => f()).toList()); // expect: [1, 2, 3, 5, 6]
  print(fs.map((f) => f()).toList()); // expect: [1, 2, 3, 6, 7]
  final l = [1, 2];
  l[0] |= 6;
  l[1]++;
  l[0] <<= 2;
  print(l); // expect: [28, 3]
  final m = {'a': 1};
  m['a'] = m['a']! + 1;
  m['b'] ??= 5;
  print(m); // expect: {a: 2, b: 5}
  int z;
  for (z in l) {
    fs.add(() => z);
  }
  print(fs.last()); // expect: 3
}
