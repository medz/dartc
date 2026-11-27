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
  t(r'\p{L}', ['p{L}', 'L'], u: false); // expect: \p{L} u=false i=false [p{L}, null]
  t(r'\P{L}', ['P{L}', 'L'], u: false); // expect: \P{L} u=false i=false [P{L}, null]
  t(r'[\p{L}]+', ['p{L}', 'L'], u: false); // expect: [\p{L}]+ u=false i=false [p{L}, L]
  final words = ['\u017f', '\u212a', 'k', 'S', '\u03c3', '\u03a3', '\u{10428}'];
  for (final p in [
    r'\w',
    'k',
    r'\p{Lt}',
    r'[A-Z]',
    '\u03c3',
    '[\u{10400}-\u{10410}]',
  ]) {
    t(p, words, u: true, i: true);
    if (p.length < 6) t(p, words, u: false, i: true);
  }
  // expect: \w u=true i=true [ſ, K, k, S, null, null, null]
  // expect: \w u=false i=true [null, null, k, S, null, null, null]
  // expect: k u=true i=true [null, K, k, null, null, null, null]
  // expect: k u=false i=true [null, null, k, null, null, null, null]
  // expect: \p{Lt} u=true i=true [null, null, null, null, null, null, null]
  // expect: [A-Z] u=true i=true [ſ, K, k, S, null, null, null]
  // expect: [A-Z] u=false i=true [null, null, k, S, null, null, null]
  // expect: σ u=true i=true [null, null, null, null, σ, Σ, null]
  // expect: σ u=false i=true [null, null, null, null, σ, Σ, null]
  // expect: [𐐀-𐐐] u=true i=true [null, null, null, null, null, null, 𐐨]
}
