Future<void> main() async {
  dynamic n = 255;
  print(n.toRadixString(16)); // expect: ff
  print(n.toString()); // expect: 255
  dynamic d = 2.5;
  print(d.toStringAsFixed(2)); // expect: 2.50
  print((
    n.compareTo(3),
    d.compareTo(3),
    n.remainder(4),
    n.gcd(5),
    n.bitLength,
    n.isEven,
  )); // expect: (1, -1, 3, 5, 8, false)
  final c = n.compareTo;
  print(c(3)); // expect: 1
  dynamic b = true;
  print(b.toString()); // expect: true
  print(n.modPow(3, 7)); // expect: 6
  print(
    n.toRadixString,
  ); // expect: Closure: (int) => String from Function 'toRadixString':.
  print(sync().runtimeType); // expect: _SyncStarIterable<dynamic>
  print(sync2() is Iterable<int>); // expect: true
  Iterable<Object> o = sync2();
  print(o is Iterable<int>); // expect: true
  Iterable x = sync3();
  print((
    x is Iterable<int>,
    x.runtimeType,
  )); // expect: (false, _SyncStarIterable<dynamic>)
  dynamic y = sync4();
  print((y is Iterable<int>,)); // expect: (false)
  try {
    n.toRadixString('a');
  } catch (e) {
    print(e.runtimeType);
  }
  // expect: _TypeError
}

Iterable<int> sync2() sync* {
  yield 1;
}

Iterable<T> gen<T>(T a) sync* {
  yield a;
}

Iterable sync3() sync* {
  yield 1;
}

sync4() sync* {
  yield 1;
}

Object sync() sync* {
  yield 1;
}
