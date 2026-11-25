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

const inputs = ['ab', 'aB', 'Ab', '\n', 'x\na\ny', 'aA', 'ac', 'Bc', ''];

void main() {
  for (final p in [
    r'(?i:a)b',
    r'(?-i:a)b',
    r'(?i-i:a)',
    r'(?ii:a)',
    r'(?:a)',
    r'(?-:a)',
    r'(?i-:a)',
    r'(?-i:a)',
    r'(?ims:a)',
    r'(?i)a',
    r'(?x:a)',
    r'(?i',
    r'(?i:a',
    r'(?i-m:a)(?m:^b)',
    r'(?s:.)',
    r'(?-s:.)',
    r'(?m:^a$)',
    r'(?i:(a)\1)',
    r'((?i:a))\1',
    r'(?i:[a-c])+',
    r'(?u:a)',
    r'(?g:a)',
    r'(?i-ms:A)',
    r'(?i:\b\w)',
    r'(?i:a|b)c',
    r'(?<n>(?i:a))',
    r'(?^i:a)',
    r'(?i-s-m:a)',
    r'(?--i:a)',
    r'(?i:)',
    r'(?-ims:.)',
    r'(?smi:.)',
  ]) {
    t(p, inputs, u: false);
    t(p, inputs, i: true, m: true, s: true);
  }
  // expect: (?i:a)b u=false i=false [ab, null, Ab, null, null, null, null, null, null]
  // expect: (?i:a)b u=true i=true [ab, aB, Ab, null, null, null, null, null, null]
  // expect: (?-i:a)b u=false i=false [ab, null, null, null, null, null, null, null, null]
  // expect: (?-i:a)b u=true i=true [ab, aB, null, null, null, null, null, null, null]
  // expect: (?i-i:a) u=false i=false FormatException FormatException: Repeated flag in flag group
  // expect: (?i-i:a)
  // expect: (?i-i:a) u=true i=true FormatException FormatException: Repeated flag in flag group
  // expect: (?i-i:a)
  // expect: (?ii:a) u=false i=false FormatException FormatException: Repeated flag in flag group
  // expect: (?ii:a)
  // expect: (?ii:a) u=true i=true FormatException FormatException: Repeated flag in flag group
  // expect: (?ii:a)
  // expect: (?:a) u=false i=false [a, a, null, null, a, a, a, null, null]
  // expect: (?:a) u=true i=true [a, a, A, null, a, a, a, null, null]
  // expect: (?-:a) u=false i=false FormatException FormatException: Invalid flag group
  // expect: (?-:a)
  // expect: (?-:a) u=true i=true FormatException FormatException: Invalid flag group
  // expect: (?-:a)
  // expect: (?i-:a) u=false i=false [a, a, A, null, a, a, a, null, null]
  // expect: (?i-:a) u=true i=true [a, a, A, null, a, a, a, null, null]
  // expect: (?-i:a) u=false i=false [a, a, null, null, a, a, a, null, null]
  // expect: (?-i:a) u=true i=true [a, a, null, null, a, a, a, null, null]
  // expect: (?ims:a) u=false i=false [a, a, A, null, a, a, a, null, null]
  // expect: (?ims:a) u=true i=true [a, a, A, null, a, a, a, null, null]
  // expect: (?i)a u=false i=false FormatException FormatException: Invalid group
  // expect: (?i)a
  // expect: (?i)a u=true i=true FormatException FormatException: Invalid group
  // expect: (?i)a
  // expect: (?x:a) u=false i=false FormatException FormatException: Invalid group
  // expect: (?x:a)
  // expect: (?x:a) u=true i=true FormatException FormatException: Invalid group
  // expect: (?x:a)
  // expect: (?i u=false i=false FormatException FormatException: Invalid group
  // expect: (?i
  // expect: (?i u=true i=true FormatException FormatException: Invalid group
  // expect: (?i
  // expect: (?i:a u=false i=false FormatException FormatException: Unterminated group
  // expect: (?i:a
  // expect: (?i:a u=true i=true FormatException FormatException: Unterminated group
  // expect: (?i:a
  // expect: (?i-m:a)(?m:^b) u=false i=false [null, null, null, null, null, null, null, null, null]
  // expect: (?i-m:a)(?m:^b) u=true i=true [null, null, null, null, null, null, null, null, null]
  // expect: "(?s:.) u=false i=false [a, a, A, "
  // expect: , x, a, a, B, null]
  // expect: "(?s:.) u=true i=true [a, a, A, "
  // expect: , x, a, a, B, null]
  // expect: (?-s:.) u=false i=false [a, a, A, null, x, a, a, B, null]
  // expect: (?-s:.) u=true i=true [a, a, A, null, x, a, a, B, null]
  // expect: (?m:^a$) u=false i=false [null, null, null, null, a, null, null, null, null]
  // expect: (?m:^a$) u=true i=true [null, null, null, null, a, null, null, null, null]
  // expect: (?i:(a)\1) u=false i=false [null, null, null, null, null, aA, null, null, null]
  // expect: (?i:(a)\1) u=true i=true [null, null, null, null, null, aA, null, null, null]
  // expect: ((?i:a))\1 u=false i=false [null, null, null, null, null, null, null, null, null]
  // expect: ((?i:a))\1 u=true i=true [null, null, null, null, null, aA, null, null, null]
  // expect: (?i:[a-c])+ u=false i=false [ab, aB, Ab, null, a, aA, ac, Bc, null]
  // expect: (?i:[a-c])+ u=true i=true [ab, aB, Ab, null, a, aA, ac, Bc, null]
  // expect: (?u:a) u=false i=false FormatException FormatException: Invalid group
  // expect: (?u:a)
  // expect: (?u:a) u=true i=true FormatException FormatException: Invalid group
  // expect: (?u:a)
  // expect: (?g:a) u=false i=false FormatException FormatException: Invalid group
  // expect: (?g:a)
  // expect: (?g:a) u=true i=true FormatException FormatException: Invalid group
  // expect: (?g:a)
  // expect: (?i-ms:A) u=false i=false [a, a, A, null, a, a, a, null, null]
  // expect: (?i-ms:A) u=true i=true [a, a, A, null, a, a, a, null, null]
  // expect: (?i:\b\w) u=false i=false [a, a, A, null, x, a, a, B, null]
  // expect: (?i:\b\w) u=true i=true [a, a, A, null, x, a, a, B, null]
  // expect: (?i:a|b)c u=false i=false [null, null, null, null, null, null, ac, Bc, null]
  // expect: (?i:a|b)c u=true i=true [null, null, null, null, null, null, ac, Bc, null]
  // expect: (?<n>(?i:a)) u=false i=false [a, a, A, null, a, a, a, null, null]
  // expect: (?<n>(?i:a)) u=true i=true [a, a, A, null, a, a, a, null, null]
  // expect: (?^i:a) u=false i=false FormatException FormatException: Invalid group
  // expect: (?^i:a)
  // expect: (?^i:a) u=true i=true FormatException FormatException: Invalid group
  // expect: (?^i:a)
  // expect: (?i-s-m:a) u=false i=false FormatException FormatException: Multiple dashes in flag group
  // expect: (?i-s-m:a)
  // expect: (?i-s-m:a) u=true i=true FormatException FormatException: Multiple dashes in flag group
  // expect: (?i-s-m:a)
  // expect: (?--i:a) u=false i=false FormatException FormatException: Multiple dashes in flag group
  // expect: (?--i:a)
  // expect: (?--i:a) u=true i=true FormatException FormatException: Multiple dashes in flag group
  // expect: (?--i:a)
  // expect: (?i:) u=false i=false [, , , , , , , , ]
  // expect: (?i:) u=true i=true [, , , , , , , , ]
  // expect: (?-ims:.) u=false i=false [a, a, A, null, x, a, a, B, null]
  // expect: (?-ims:.) u=true i=true [a, a, A, null, x, a, a, B, null]
  // expect: "(?smi:.) u=false i=false [a, a, A, "
  // expect: , x, a, a, B, null]
  // expect: "(?smi:.) u=true i=true [a, a, A, "
  // expect: , x, a, a, B, null]
}
