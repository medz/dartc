import 'dart:math';

import 'package:dartc/src/optimizer/state_map.dart';
import 'package:test/test.dart';

void main() {
  test(
    'versions preserve earlier entries across colliding updates and joins',
    () {
      final keys = [for (var i = 0; i < 80; i++) _Key(i, i % 7 - 3)];
      final random = Random(813);
      var current = const StateMap<_Key, int>.empty();
      final expected = <_Key, int>{};
      final versions = <(StateMap<_Key, int>, Map<_Key, int>)>[];
      for (var i = 0; i < 240; i++) {
        versions.add((current, {...expected}));
        final key = keys[random.nextInt(keys.length)];
        final value = random.nextInt(1000);
        current = current.withEntry(key, value);
        expected[key] = value;
      }
      expect(Map.fromEntries(current.entries), expected);
      final rebuilt = StateMap.fromEntries(expected.entries.toList().reversed);
      expect(current, rebuilt);
      expect(current.hashCode, rebuilt.hashCode);
      for (final (version, old) in versions) {
        expect(Map.fromEntries(version.entries), old);
        final joined = version.merge(current, (_, a, b) => max(a ?? 0, b ?? 0));
        expect(Map.fromEntries(joined.entries), {
          for (final key in {...old.keys, ...expected.keys})
            key: max(old[key] ?? 0, expected[key] ?? 0),
        });
        expect(Map.fromEntries(version.entries), old);
      }
    },
  );

  test(
    'missing overrides are joined with their declared default on either side',
    () {
      const empty = StateMap<int, int>.empty();
      final written = empty.withEntry(1, 4).withEntry(2, 8);
      int join(int key, int? left, int? right) => (left ?? 1) | (right ?? 1);
      expect(Map.fromEntries(written.merge(empty, join).entries), {1: 5, 2: 9});
      expect(Map.fromEntries(empty.merge(written, join).entries), {1: 5, 2: 9});
    },
  );

  test('sibling versions only rejoin changed hash paths', () {
    final base = StateMap.fromEntries([
      for (var i = 0; i < 4096; i++) MapEntry(i, i),
    ]);
    final left = base.withEntry(17, 5000), right = base.withEntry(65, 6000);
    var compared = 0;
    final joined = left.merge(right, (_, a, b) {
      compared++;
      return max(a!, b!);
    });
    expect(joined[17], 5000);
    expect(joined[65], 6000);
    expect(joined[2048], 2048);
    expect(base[17], 17);
    expect(joined.differences(base).toSet(), {
      (key: 17, before: 17, after: 5000),
      (key: 65, before: 65, after: 6000),
    });
    final removed = joined.withoutKey(17);
    expect(removed.differences(joined).single, (
      key: 17,
      before: 5000,
      after: null,
    ));
    expect(
      compared,
      lessThan(100),
      reason: 'shared state must not be rescanned at every join',
    );
    expect(identical(base.withEntry(17, 17), base), isTrue);
  });
}

final class _Key(final int id, final int hash) {
  @override
  int get hashCode => hash;
  @override
  bool operator ==(Object other) => other is _Key && other.id == id;
}
