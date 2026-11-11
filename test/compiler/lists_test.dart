@Tags(['assets', 'native'])
library;

import 'dart:io';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';
import 'fixtures/lists.dart' as sdk;
import 'fixtures/lists_ffi.dart';

void main() {
  late Lists native;
  setUpAll(() {
    native = Lists();
    addTearDown(native.close);
  });

  test('literal, empty and filled Lists grow and preserve indexed values', () {
    for (final count in [0, 1, 8, 10000]) {
      for (final mode in [0, 1, 2]) {
        final expected = count * (count - 1) ~/ 2 + (mode == 1 ? 0 : 8);
        expect(sdk.listValues(count, mode), expected);
        expect(native.values(count, mode), expected);
      }
    }
    for (final count in [0, 8, 10000]) {
      expect(sdk.listDoubles(count), count * 0.5 + 1.5);
      expect(native.doubles(count), count * 0.5 + 1.5);
    }
    for (final count in [1, 8, 10000]) {
      for (final index in [0, count - 1]) {
        expect(sdk.listFixed(count, index), count * 100 + 9);
        expect(native.fixed(count, index), count * 100 + 9);
      }
    }
  });

  test('shrinking clears removed references and growing inserts null', () {
    for (final count in [0, 1, 3, 8, 10000]) {
      final expected = count == 0 ? 0 : 1 + (count - 1) * 10;
      expect(sdk.listResize(count), expected);
      expect(native.resize(count), expected);
    }
  });

  test(
    'generic elements, shared fills, cycles and globals survive moving GC',
    () {
      for (final count in [0, 10, 40000]) {
        final expected = 69 + count * (count - 1) ~/ 2;
        expect(sdk.listReferences(count), expected);
        expect(native.references(count), expected);
        expect(native.saved(0), 23);
        expect(native.saved(count + 2), count == 0 ? 23 : count - 1);
        expect(sdk.listCycles(count), count == 0 ? 41 : count + 40);
        expect(native.cycles(count), count == 0 ? 41 : count + 40);
      }
    },
  );

  test(
    'covariant writes check the actual type before bounds or mutability',
    () {
      for (final index in [-0x8000000000000000, -1, 1, 0x7fffffffffffffff]) {
        for (final (mode, expected) in [(1, 17), (2, 17), (3, 27)]) {
          expect(sdk.listFailures(mode, index), expected);
          expect(native.failures(mode, index), expected);
        }
      }
      for (final (mode, index, expected) in [
        (0, -1, 17),
        (6, -1, 17),
        (4, 0, 27),
        (5, 0, 27),
        (7, 0, 37),
        (8, 0, 37),
        (9, 0, 27),
      ]) {
        expect(sdk.listFailures(mode, index), expected);
        expect(native.failures(mode, index), expected);
      }
    },
  );

  test(
    'user List implementations and extracted functions keep virtual dispatch',
    () {
      for (final (mode, expected) in [(0, 312), (1, 217)]) {
        expect(sdk.listDispatch(mode), expected);
        expect(native.dispatch(mode), expected);
      }
      for (final count in [1, 8]) {
        expect(sdk.listFactories(count), count * 10 + 3);
        expect(native.factories(count), count * 10 + 3);
      }
    },
  );

  test(
    'index assignment evaluates receiver, index and value once before checking',
    () {
      for (final (index, expected) in [(0, 12359), (-1, 123457), (1, 123457)]) {
        expect(sdk.listOrder(index), expected);
        expect(native.order(index), expected);
      }
    },
  );

  test('oversized element counts cannot wrap into small allocations', () async {
    final file = NativeAssets(Target.host())
        .file('compiler/entry_lists_overflow');
    final result = await Process.run(file.path, []);
    expect(result.exitCode, 255);
    expect(result.stdout, isEmpty);
    expect(result.stderr, 'Unhandled exception:\nOut of Memory\n');
  });
}
