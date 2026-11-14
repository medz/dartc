import 'text_conversion.dart' show check, rejects, same;

void main() {
  final generate = Iterable<int>.generate;
  same(generate(4), [0, 1, 2, 3], 'generator default and constructor value');
  final empty = const Iterable<int>.empty();
  check(empty.isEmpty, 'empty iterable');
  check(
    identical(empty, const Iterable<int>.empty()),
    'empty constant identity',
  );
  check(
    Iterable<String>.generate(0).isEmpty,
    'zero length skips default generator type',
  );
  check(
    rejects<ArgumentError>(() => Iterable<String>.generate(1)),
    'invalid default generator',
  );
  var generated = 0;
  final source = generate(6, (index) {
    generated++;
    return index;
  });
  check(generated == 0 && source.length == 6, 'generation remains lazy');
  same(source, [0, 1, 2, 3, 4, 5], 'generated values');
  same(source, [0, 1, 2, 3, 4, 5], 'generated values are recomputed');
  check(generated == 12, 'no value caching');

  var factories = 0;
  final withIterator = Iterable<int>.withIterator;
  final fresh = withIterator(() => [++factories, 42].iterator);
  check(factories == 0, 'iterator factory is lazy');
  same(fresh, [1, 42], 'first iterator');
  same(fresh, [2, 42], 'fresh iterator');
  check(factories == 2, 'one factory per traversal');

  final trace = <String>[];
  final pipeline =
      generate(6, (value) {
            trace.add('g$value');
            return value;
          })
          .where((value) {
            trace.add('w$value');
            return value.isEven;
          })
          .skip(1)
          .map((value) {
            trace.add('m$value');
            return value * 10;
          })
          .take(2);
  check(trace.isEmpty, 'pipeline remains lazy');
  same(pipeline, [20, 40], 'pipeline result');
  same(trace, [
    'g0',
    'w0',
    'g1',
    'w1',
    'g2',
    'w2',
    'm2',
    'g3',
    'w3',
    'g4',
    'w4',
    'm4',
  ], 'early stop and callback order');
  trace.clear();
  same(pipeline, [20, 40], 'pipeline can be traversed again');
  check(trace.last == 'm4', 'take does not request later source');

  final values = <Object?>[1, 'x', null, 2.5, (3, 'three')];
  same(values.whereType<num>(), [1, 2.5], 'type filter');
  same(values.whereType<Null>(), [null], 'null type filter');
  check(values.whereType<Never>().isEmpty, 'bottom type filter');
  final records = values.whereType<(int, String)>();
  check(
    records.single.$1 == 3 && records.single.$2 == 'three',
    'record type filter',
  );
  final cast = values.cast<int>().iterator;
  check(cast.moveNext() && cast.current == 1, 'lazy cast first value');
  check(
    rejects<TypeError>(() {
      cast.moveNext();
      cast.current;
    }),
    'lazy cast failure',
  );

  same([1, 2].followedBy([3, 4]), [1, 2, 3, 4], 'followedBy order');
  same([1, 2, 3].expand((value) => [value, -value]), [
    1,
    -1,
    2,
    -2,
    3,
    -3,
  ], 'expand order');
  same([4, 5].indexed.map((entry) => '${entry.$1}:${entry.$2}'), [
    '0:4',
    '1:5',
  ], 'indexed records');
  same([1, 2, 3, 1].takeWhile((value) => value < 3), [
    1,
    2,
  ], 'takeWhile prefix');
  same([1, 2, 3, 1].skipWhile((value) => value < 3), [
    3,
    1,
  ], 'skipWhile stops checking');
  check(
    [1, 2, 3].fold<String>('', (text, value) => '$text$value') == '123',
    'fold order',
  );
  check(
    [1, 2, 3].reduce((left, right) => left * 10 + right) == 123,
    'reduce order',
  );
  check([1, 2, 3].join(':') == '1:2:3', 'join');
  check(generate(3, (index) => index % 2).toSet().length == 2, 'toSet');
  check(source.contains(2) && !source.contains(Object()), 'contains');

  var probes = 0;
  check(
    [1, 2, 3].any((value) {
          probes++;
          return value == 2;
        }) &&
        probes == 2,
    'any short circuit',
  );
  probes = 0;
  check(
    ![1, 2, 3].every((value) {
          probes++;
          return value < 2;
        }) &&
        probes == 2,
    'every short circuit',
  );
  var fallbacks = 0;
  int fallback() {
    fallbacks++;
    return 9;
  }

  final numbers = generate(4);
  check(numbers.first == 0 && numbers.last == 3, 'first and last');
  check(
    numbers.firstWhere((value) => value > 1, orElse: fallback) == 2,
    'firstWhere',
  );
  check(
    numbers.lastWhere((value) => value.isEven, orElse: fallback) == 2,
    'lastWhere',
  );
  check(
    numbers.singleWhere((value) => value == 2, orElse: fallback) == 2,
    'singleWhere',
  );
  check(fallbacks == 0, 'fallback is lazy');
  check(
    numbers.firstWhere((_) => false, orElse: fallback) == 9 && fallbacks == 1,
    'missing fallback',
  );
  check(rejects<StateError>(() => empty.first), 'empty first');
  check(rejects<StateError>(() => empty.last), 'empty last');
  check(
    rejects<StateError>(() => empty.reduce((a, b) => a + b)),
    'empty reduce',
  );
  check(rejects<StateError>(() => numbers.single), 'multiple single');
  check(
    rejects<StateError>(() => numbers.singleWhere((_) => true)),
    'multiple matches',
  );
  check(rejects<RangeError>(() => numbers.elementAt(-1)), 'negative index');
  check(rejects<RangeError>(() => numbers.elementAt(4)), 'large index');
  check(rejects<RangeError>(() => numbers.take(-1)), 'negative take');
  check(rejects<RangeError>(() => numbers.skip(-1)), 'negative skip');

  final marker = Object();
  final failing = withIterator(() => throw marker);
  var caught = false;
  try {
    failing.iterator;
  } catch (error) {
    caught = identical(error, marker);
  }
  check(caught, 'iterator factory exception identity');
  final delayed = generate(4, (value) => value == 2 ? throw marker : value);
  same(delayed.take(2), [0, 1], 'take avoids later failure');
  caught = false;
  try {
    delayed.toList();
  } catch (error) {
    caught = identical(error, marker);
  }
  check(caught, 'generator failure identity');

  final retained = [7, 8].map((value) => value + 10);
  final iterator = retained.iterator;
  check(
    iterator.moveNext() && iterator.current == 17,
    'iterator before collection',
  );
  for (var index = 0; index < 2000; index++) {
    final garbage = List<String>.filled(64, index.toString());
    check(garbage.first.isNotEmpty, 'allocation pressure');
  }
  check(
    iterator.moveNext() && iterator.current == 18,
    'iterator after collection',
  );
  check(
    !iterator.moveNext() && !iterator.moveNext(),
    'completed iterator remains done',
  );
  same(retained, [17, 18], 'retained iterable remains reusable');
  print('iterables:ok');
}
