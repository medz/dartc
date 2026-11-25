void main() {
  final r = RegExp(r'(\w+)@(\w+)\.com');
  print(r.hasMatch('joe@x.com')); // expect: true
  final m = r.firstMatch('hi joe@site.com bye')!;
  print(m.group(0)); // expect: joe@site.com
  print(m[1]); // expect: joe
  print(m.start); // expect: 3
  print('a1b22c'.replaceAll(RegExp(r'\d+'), '#')); // expect: a#b#c
  print('a1b22c'.split(RegExp(r'\d'))); // expect: [a, b, , c]
  print(
    RegExp('a|b').allMatches('cab').map((m) => m[0]).toList(),
  ); // expect: [a, b]
  print(
    RegExp(r'^[a-z]+$', caseSensitive: false).hasMatch('ABC'),
  ); // expect: true
  print(
    RegExp(r'(?<y>\d{4})').firstMatch('in 2024')!.namedGroup('y'),
  ); // expect: 2024
}
