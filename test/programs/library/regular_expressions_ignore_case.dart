// long
void t(
  String p,
  List<String> inputs, {
  bool u = true,
  bool i = false,
  bool m = false,
  bool s = false,
}) {
  try {
    final r = RegExp(p, unicode: u, caseSensitive: !i, multiLine: m, dotAll: s);
    print('$p u=$u i=$i ${[for (final x in inputs) r.stringMatch(x)]}');
  } catch (e) {
    print('$p u=$u i=$i ${e.runtimeType} $e');
  }
}

void main() {
  t(r'\p{L}', ['p{L}', 'L'], u: false);
  t(r'\P{L}', ['P{L}', 'L'], u: false);
  t(r'[\p{L}]+', ['p{L}', 'L'], u: false);
  final words = [
    '\u017f',
    '\u212a',
    'k',
    's',
    'S',
    '\u03c3',
    '\u03a3',
    '\u01c5',
    '\u01c6',
    '\u{10400}',
    '\u{10428}',
    '\u0345',
    '\u1fbe',
  ];
  for (final p in [
    r'\w',
    r'\W',
    'k',
    's',
    r'\p{Lt}',
    r'[A-Z]',
    '[\u00df]',
    '\u03c3',
    '\u01c5',
    '[\u{10400}-\u{10410}]',
    '\u0345',
  ]) {
    for (final u in [true, false]) {
      t(p, words, u: u, i: true);
    }
  }
}
