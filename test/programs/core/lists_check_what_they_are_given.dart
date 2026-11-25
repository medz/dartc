void go(void Function() f) {
  try {
    f();
    print('ok');
  } catch (e) {
    print(e);
  }
}

void main() {
  final l = [1, 2, 3];
  go(() => l[3]); // expect: RangeError (length): Invalid value: Not in inclusive range 0..2: 3
  go(() => l[-1]); // expect: RangeError (length): Invalid value: Not in inclusive range 0..2: -1
  go(() => l[5] = 1); // expect: RangeError (index): Invalid value: Not in inclusive range 0..2: 5
  go(() => <int>[][0]); // expect: RangeError (length): Invalid value: Valid value range is empty: 0
  go(
    () => const [1][1],
  ); // expect: RangeError (length): Invalid value: Only valid value is 0: 1
  go(() => List.filled(2, 0)[2]); // expect: RangeError (length): Invalid value: Not in inclusive range 0..1: 2
  go(() => List.filled(-1, 0)); // expect: RangeError (length): Invalid value: Not in inclusive range 0..576460752303423487: -1
  go(
    () => List.filled(1, 0).add(1),
  ); // expect: Unsupported operation: Cannot add to a fixed-length list
  go(
    () => (const [1] as List).add(1),
  ); // expect: Unsupported operation: Cannot add to an unmodifiable list
  go(
    () => List.unmodifiable([1])[0] = 2,
  ); // expect: Unsupported operation: Cannot modify an unmodifiable list
  go(() => <int>[].first); // expect: Bad state: No element
  go(() => <int>[].last); // expect: Bad state: No element
  go(() => <int>[].single); // expect: Bad state: No element
  go(() => l.single); // expect: Bad state: Too many elements
  go(() => <int>[].reduce((a, b) => a)); // expect: Bad state: No element
  go(() => l.removeAt(7)); // expect: RangeError (length): Invalid value: Not in inclusive range 0..2: 7
  go(
    () => l.insert(9, 1),
  ); // expect: RangeError: Invalid value: Not in inclusive range 0..3: 9
  go(
    () => l.sublist(2, 1),
  ); // expect: RangeError (end): Invalid value: Not in inclusive range 2..3: 1
  go(() => l.firstWhere((x) => x > 5)); // expect: Bad state: No element
  go(() {
    for (final x in l) {
      l.add(x);
    }
  }); // expect: Concurrent modification during iteration: Instance(length:4) of '_GrowableList'.
  go(
    () => (l as List<Object>).add('x'),
  ); // expect: type 'String' is not a subtype of type 'int' of 'value'
  go(() {
    dynamic d = l;
    d.add('x');
  }); // expect: type 'String' is not a subtype of type 'int' of 'value'
  go(() {
    List<num> n = l;
    n[0] = 1.5;
  }); // expect: type 'double' is not a subtype of type 'int' of 'value'
  go(() {
    dynamic d = l;
    List<String> s = d;
  }); // expect: type 'List<int>' is not a subtype of type 'List<String>'
  go(() => 'abc'[3]); // expect: RangeError (index): Invalid value: Not in inclusive range 0..2: 3
  go(() => 'abc'.codeUnitAt(3)); // expect: RangeError (length): Invalid value: Not in inclusive range 0..2: 3
  go(
    () => ''[0],
  ); // expect: RangeError (index): Invalid value: Valid value range is empty: 0
  go(
    () => 'abc'.substring(2, 1),
  ); // expect: RangeError (end): Invalid value: Not in inclusive range 2..3: 1
  go(() => int.parse('zz'));
  // expect: FormatException: Invalid radix-10 number (at character 1)
  // expect: zz
  // expect: ^
  // expect:
  go(() => double.parse('zz'));
  // expect: FormatException: Invalid double
  // expect: zz
  go(() => l.elementAt(9)); // expect: RangeError (length): Invalid value: Not in inclusive range 0..3: 9
  go(() => Iterable.generate(3).elementAt(3)); // expect: RangeError (index): Index out of range: index should be less than 3: 3
  go(() => 1 ~/ (l[0] - 1)); // expect: IntegerDivisionByZeroException
  go(() => 1 << (l[0] - 2)); // expect: Invalid argument(s): -1
  go(
    () => (0.0 / (l[0] - 1)).toInt(),
  ); // expect: Unsupported operation: Infinity or NaN toInt
  go(
    () => (null as dynamic)!,
  ); // expect: Null check operator used on a null value
  go(() => throw 'text'); // expect: text
  go(() => throw 5); // expect: 5
  go(() => throw Exception('boom')); // expect: Exception: boom
  go(() => throw StateError('bad')); // expect: Bad state: bad
  go(
    () => throw ArgumentError.value(3, 'n', 'too big'),
  ); // expect: Invalid argument (n): too big: 3
  go(() => throw UnsupportedError('u')); // expect: Unsupported operation: u
  go(() => throw FormatException('f', 'abc', 1));
  // expect: FormatException: f (at character 2)
  // expect: abc
  // expect: " ^"
  // expect:
  go(
    () => throw RangeError.range(5, 0, 3, 'r'),
  ); // expect: RangeError (r): Invalid value: Not in inclusive range 0..3: 5
  go(() => throw UnimplementedError()); // expect: UnimplementedError
  go(
    () => throw ConcurrentModificationError(),
  ); // expect: Concurrent modification during iteration.
  go(
    () => throw ArgumentError.notNull('z'),
  ); // expect: Invalid argument(s) (z): Must not be null
  go(() => throw AssertionError('a')); // expect: Assertion failed: "a"
}
