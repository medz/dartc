@Tags(['assets', 'native'])
library;

import 'package:test/test.dart';

import 'fixtures/closures_ffi.dart';

void main() {
  late Closures native;
  setUpAll(() {
    native = Closures();
    addTearDown(native.close);
  });

  test(
    'escaped siblings share mutable cells across entries and collections',
    () {
      expect(native.counter(0, 2), 2);
      for (var i = 1; i <= 3; i++) {
        expect(native.collect(40000), 39999);
        expect(native.counter(1, 3), 2 + 3 * i);
        expect(native.collect(40000), 39999);
        expect(native.counter(2, 0), 2 + 3 * i);
      }
    },
  );

  test(
    'nested closures, loop cells and captured values survive collection',
    () {
      for (final count in [0, 40000]) {
        expect(native.nested(count), 733);
        expect(native.iteration(count), 1232);
        expect(native.captures(count), 34145725);
        expect(native.afterExit(1, count), 5);
        expect(native.afterExit(0, count), 12);
        expect(native.generic(count), 8189);
      }
    },
  );

  test('closure throws preserve captured aliases across catch and finally', () {
    for (final count in [0, 40000]) {
      expect(native.invocationFailure(count), 2323);
    }
  });

  test('typed calls preserve recursion and positional and named defaults', () {
    expect(native.recursive(0), 1);
    expect(native.recursive(5), 120);
    expect(native.defaults(2), 211717);
  });
}
