void main() {
  const words = [
    '',
    'a',
    'abc',
    'Hello World',
    'é中😀',
    '  x y  ',
    'aXbXc',
    'abĀ',
  ];
  // expect: [] 0 1 true false  false -1 -1 false false [] [] [] [] []   [] []   -1 false [      ] [......]
  // expect: [a] 1 170824770 false true a false -1 -1 true false [a] [a] [a] [a] [a] a a [97] [97] aa aa -1 false [     a] [a.....]
  // expect: a 97 [a] []
  // expect: [abc] 3 756227931 false true abc true 1 -1 true true [abc] [abc] [abc] [abc] [a, b, c] abc aéc [97, 98, 99] [97, 98, 99] abcabc abcabc 0 true [   abc] [abc...]
  // expect: a 97 [abc] []
  // expect: b 98 [bc] [a]
  // expect: c 99 [c] [ab]
  // expect: [Hello World] 11 12212756 false true Hello World false -1 -1 false false [Hello World] [Hello World] [Hello World] [Hello World] [H, e, l, l, o,  , W, o, r, l, d] Hello World Hello World [72, 101, 108, 108, 111, 32, 87, 111, 114, 108, 100] [72, 101, 108, 108, 111, 32, 87, 111, 114, 108, 100] Hello WorldHello World Hello WorldHello World -1 false [Hello World] [Hello World]
  // expect: H 72 [Hello World] []
  // expect: e 101 [ello World] [H]
  // expect: l 108 [llo World] [He]
  // expect: l 108 [lo World] [Hel]
  // expect: o 111 [o World] [Hell]
  // expect: "  32 [ World] [Hello]"
  // expect: W 87 [World] [Hello ]
  // expect: o 111 [orld] [Hello W]
  // expect: r 114 [rld] [Hello Wo]
  // expect: l 108 [ld] [Hello Wor]
  // expect: d 100 [d] [Hello Worl]
  // expect: [é中😀] 4 15908013 false true é中😀 false -1 -1 false false [é中😀] [é中😀] [é中😀] [é中😀] [é, 中, �, �] é中😀 é中😀 [233, 20013, 55357, 56832] [233, 20013, 128512] é中😀é中😀 é中😀é中😀 1 false [  é中😀] [é中😀..]
  // expect: é 233 [é中😀] []
  // expect: 中 20013 [中😀] [é]
  // expect: � 55357 [😀] [é中]
  // expect: � 56832 [�] [é中�]
  // expect: [  x y  ] 7 849804442 false true   x y   false -1 -1 false false [x y] [x y  ] [  x y] [  x y  ] [ ,  , x,  , y,  ,  ]   x y     x y   [32, 32, 120, 32, 121, 32, 32] [32, 32, 120, 32, 121, 32, 32]   x y    x y     x y    x y   -1 false [  x y  ] [  x y  ]
  // expect: "  32 [  x y  ] []"
  // expect: "  32 [ x y  ] [ ]"
  // expect: x 120 [x y  ] [  ]
  // expect: "  32 [ y  ] [  x]"
  // expect: y 121 [y  ] [  x ]
  // expect: "  32 [  ] [  x y]"
  // expect: "  32 [ ] [  x y ]"
  // expect: [aXbXc] 5 648933285 false true aXbXc true 2 3 true true [aXbXc] [aXbXc] [aXbXc] [a, b, c] [a, X, b, X, c] a--b--c aXéXc [97, 88, 98, 88, 99] [97, 88, 98, 88, 99] aXbXcaXbXc aXbXcaXbXc -1 false [ aXbXc] [aXbXc.]
  // expect: a 97 [aXbXc] []
  // expect: X 88 [XbXc] [a]
  // expect: b 98 [bXc] [aX]
  // expect: X 88 [Xc] [aXb]
  // expect: c 99 [c] [aXbX]
  // expect: [abĀ] 3 81697899 false true abĀ true 1 -1 true false [abĀ] [abĀ] [abĀ] [abĀ] [a, b, Ā] abĀ aéĀ [97, 98, 256] [97, 98, 256] abĀabĀ abĀabĀ 1 false [   abĀ] [abĀ...]
  // expect: a 97 [abĀ] []
  // expect: b 98 [bĀ] [a]
  // expect: Ā 256 [Ā] [ab]
  // expect: 😀
  // expect: hi中
  // expect: 1
  // expect: ab
  // expect: 1, 2, 3
  // expect: (a)+(b)+(c)
  // expect: a<b>ca<b>c
  // expect: aXYZc
  // expect: [1, 3]
  // expect: true
  // expect: true
  // expect: sx1y
  // expect: 1-null-é😀
  // expect: 15
  // expect: true
  // expect: 428162386
  // expect: -1
  // expect: yes
  for (final s in words) {
    print(
      '[$s] ${s.length} ${s.hashCode} ${s.isEmpty} ${s.isNotEmpty} ${s.toString()} ${s.contains('b')} ${s.indexOf('b')} ${s.lastIndexOf('X')} ${s.startsWith('a')} ${s.endsWith('c')} [${s.trim()}] [${s.trimLeft()}] [${s.trimRight()}] ${s.split('X')} ${s.split('')} ${s.replaceAll('X', '--')} ${s.replaceFirst('b', 'é')} ${s.codeUnits} ${s.runes.toList()} ${s * 2} ${s + s} ${s.compareTo('abc')} ${s == 'abc'} [${s.padLeft(6)}] [${s.padRight(6, '.')}]',
    );
    for (var i = 0; i < s.length; i++) {
      print(
        '${s[i]} ${s.codeUnitAt(i)} [${s.substring(i)}] [${s.substring(0, i)}]',
      );
    }
  }
  print(String.fromCharCode(0x1f600));
  print(String.fromCharCodes([104, 105, 0x4e2d]));
  print(String.fromCharCodes([1, 2, 3], 1, 2).length);
  print(['a', 'b'].join());
  print([1, 2, 3].join(', '));
  print(
    'a-b-c'.splitMapJoin('-', onMatch: (m) => '+', onNonMatch: (n) => '($n)'),
  );
  print('abcabc'.replaceAllMapped('b', (m) => '<${m[0]}>'));
  print('abc'.replaceRange(1, 2, 'XYZ'));
  print('b'.allMatches('abcb').map((m) => m.start).toList());
  print(
    identical(
      'a'
          'b',
      'ab',
    ),
  );
  print(identical('abc'[0], 'a'));
  final b = StringBuffer('s');
  b.write('x');
  b.write(1);
  b.writeln('y');
  b.writeAll([1, null, 'é'], '-');
  b.writeCharCode(0x1f600);
  print(b);
  print(b.length);
  b.clear();
  print(b.isEmpty);
  var t = '';
  for (var i = 0; i < 300; i++) {
    t += '$i';
  }
  print(t.hashCode);
  print('abc'.compareTo('abd'));
  switch (t.substring(0, 3)) {
    case '012':
      print('yes');
    default:
      print('no');
  }
}
