import 'dart:math';

import 'package:dartc/src/lower/dispatch.dart';
import 'package:test/test.dart';

void main() {
  void check(List<Map<int, String>> rows) {
    final (:offsets, :entries) = packRows(rows);
    expect(offsets, hasLength(rows.length));
    for (final (i, row) in rows.indexed) {
      row.forEach((column, value) {
        expect(entries[offsets[i] + column], value);
      });
    }
    // Nothing is stored that no row asked for.
    final used = {
      for (final (i, row) in rows.indexed)
        for (final column in row.keys) offsets[i] + column,
    };
    for (final (i, entry) in entries.indexed) {
      expect(entry != null, used.contains(i));
    }
  }

  test('rows share space without overlapping', () {
    final rows = [
      {0: 'a', 2: 'b'},
      {1: 'c', 3: 'd'},
      {0: 'e'},
    ];
    check(rows);
    expect(packRows(rows).entries, hasLength(5));
  });

  test('empty rows and tables', () {
    check([]);
    check([{}, {}]);
    expect(packRows<String>([{}]).entries, isEmpty);
  });

  test('a lone high column wastes no space before the table', () {
    check([
      {5: 'a'},
    ]);
    expect(
      packRows([
        {5: 'a'},
      ]).offsets.single,
      -5,
    );
  });

  test('random rows', () {
    final random = Random(5);
    for (var round = 0; round < 300; round++) {
      check([
        for (var i = random.nextInt(12); i > 0; i--)
          {
            for (var j = random.nextInt(8); j > 0; j--)
              random.nextInt(20): '$i.$j',
          },
      ]);
    }
  });
}
