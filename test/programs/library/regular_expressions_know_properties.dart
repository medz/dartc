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
  for (final p in [
    r'\p',
    r'\p{L',
    r'\pL',
    r'\p{Foo}',
    r'\p{sc=Foo}',
    r'\p{foo=bar}',
    r'[\p{Foo}]',
    r'[a-\p{Nd}]',
    r'\p{L}{2}',
    r'\p{Lu}+',
    r'[^\p{Lu}\p{gc=digit}]+',
    r'\P{Lu}+',
    r'\p{ASCII}+',
    r'\p{sc=Grek}+',
    r'\p{Script_Extensions=Greek}+',
  ]) {
    t(p, ['abCD12', 'été', 'AAAa', 'αβγ']);
  }
  // expect: \p u=true i=false FormatException FormatException: Invalid property name
  // expect: \p
  // expect: \p{L u=true i=false FormatException FormatException: Invalid property name
  // expect: \p{L
  // expect: \pL u=true i=false FormatException FormatException: Invalid property name
  // expect: \pL
  // expect: \p{Foo} u=true i=false FormatException FormatException: Invalid property name
  // expect: \p{Foo}
  // expect: \p{sc=Foo} u=true i=false FormatException FormatException: Invalid property name
  // expect: \p{sc=Foo}
  // expect: \p{foo=bar} u=true i=false FormatException FormatException: Invalid property name
  // expect: \p{foo=bar}
  // expect: [\p{Foo}] u=true i=false FormatException FormatException: Invalid property name in character class
  // expect: [\p{Foo}]
  // expect: [a-\p{Nd}] u=true i=false FormatException FormatException: Invalid character class
  // expect: [a-\p{Nd}]
  // expect: \p{L}{2} u=true i=false [ab, ét, AA, αβ]
  // expect: \p{Lu}+ u=true i=false [CD, null, AAA, null]
  // expect: [^\p{Lu}\p{gc=digit}]+ u=true i=false [ab, été, a, αβγ]
  // expect: \P{Lu}+ u=true i=false [ab, été, a, αβγ]
  // expect: \p{ASCII}+ u=true i=false [abCD12, t, AAAa, null]
  // expect: \p{sc=Grek}+ u=true i=false [null, null, null, αβγ]
  // expect: \p{Script_Extensions=Greek}+ u=true i=false [null, null, null, αβγ]
  t(r'[^\p{Zl}a]+', ['abA ']); // expect: [^\p{Zl}a]+ u=true i=false [bA]
  t(r'\p{L}', ['p{L}', 'L'], u: false); // expect: \p{L} u=false i=false [p{L}, null]
}
