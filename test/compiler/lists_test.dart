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

  test('sublist preserves ranges, overrides and selected defaults', () {
    for (final kind in [0, 1, 2, 3, 4, 5]) {
      for (final (start, end) in [
        (0, -1),
        (1, -1),
        (1, -2),
        (1, 3),
        (4, 4),
        (-1, 2),
        (2, 1),
        (0, 5),
        (0, -3),
      ]) {
        expect(native.slice(kind, start, end), sdk.listSlice(kind, start, end));
      }
    }
    expect(native.slice(0, 1, 3), 223);
    expect(native.slice(2, 1, -1), 1111);
    expect(native.slice(2, 1, -2), 1112);
  });

  test('copy constructors retain element checks and requested growability', () {
    for (final growable in [0, 1]) {
      for (final kind in [0, 1, 2, 3, 4, 5]) {
        final expected = switch (kind) {
          1 || 3 => -1,
          4 => growable == 0 ? 2000 : 1000,
          _ => (growable == 0 ? 2000 : 1000) + (kind == 5 ? 294 : 293),
        };
        expect(sdk.listCopy(kind, growable), expected);
        expect(native.copy(kind, growable), expected);
      }
    }
    for (final kind in [0, 1]) {
      for (final (failure, expected) in [
        (0, 12323245),
        (1, 123265),
        (2, 1232365),
      ]) {
        expect(sdk.listCopyProtocol(kind, failure), expected);
        expect(native.copyProtocol(kind, failure), expected);
      }
    }
  });

  test('sublist copies retain actual element types and shared objects', () {
    for (final (kind, expected) in [(0, 143), (1, 141), (2, 0)]) {
      expect(sdk.listSlicePattern(kind), expected);
      expect(native.slicePattern(kind), expected);
    }
    for (final kind in [0, 1, 2, 3]) {
      final expected = kind == 2 ? 10 : 32;
      expect(sdk.listSliceMutability(kind), expected);
      expect(native.sliceMutability(kind), expected);
    }
    expect(sdk.listSliceReferences(40000), 359);
    expect(native.sliceReferences(40000), 359);
    expect(native.saved(0), 29);
    expect(native.saved(2), 7);
  });

  test(
    'addAll dispatch checks argument types and mutability before iteration',
    () {
      for (final (mode, expected) in [(0, 310), (1, 621), (2, 310)]) {
        expect(sdk.listAppend(mode), expected);
        expect(native.append(mode), expected);
      }
      for (final (mode, expected) in [
        (0, 100),
        (1, 100),
        (2, 200),
        (3, 200),
        (4, 0),
        (5, 301),
        (6, 100),
      ]) {
        expect(sdk.listAppendFailures(mode), expected);
        expect(native.appendFailures(mode), expected);
      }
      for (final (mode, expected) in [(0, 1232325), (1, 12325), (2, 123235)]) {
        expect(sdk.listAppendProtocol(mode), expected);
        expect(native.appendProtocol(mode), expected);
      }
    },
  );

  test(
    'literal spreads check each element and preserve null and evaluation order',
    () {
      for (final (mode, expected) in [
        (0, 123232449),
        (1, 449),
        (2, 1000),
        (3, 429),
      ]) {
        expect(sdk.listSpread(mode), expected);
        expect(native.spread(mode), expected);
      }
    },
  );

  test('spread and addAll retain shared references across allocation and native calls', () {
    for (final count in [0, 40000]) {
      expect(sdk.listAppendReferences(count), count * (count - 1));
      expect(native.appendReferences(count), count * (count - 1));
      if (count != 0) {
        expect(native.saved(0), 0);
        expect(native.saved(count), 0);
        expect(native.saved(count * 2 - 1), count - 1);
      }
    }
  });

  test('iteration dispatch preserves constants, mutation checks and iterator roots', () {
    for (final (mode, expected) in [
      (0, 1234234253),
      (1, 1234251),
      (2, 12342351),
    ]) {
      expect(sdk.iteratorProtocol(mode), expected);
      expect(native.iteratorProtocol(mode), expected);
    }
    for (final count in [0, 10000]) {
      for (final (mode, expected) in [(0, count * 3), (1, 8), (2, 181)]) {
        expect(sdk.listIteration(count, mode), expected);
        expect(native.iteration(count, mode), expected);
      }
    }
    for (final (mode, expected) in [(0, 9), (1, 20), (2, 20), (3, 2)]) {
      expect(sdk.listIteratorMutation(mode), expected);
      expect(native.iteratorMutation(mode), expected);
    }
    for (final count in [0, 40000]) {
      expect(sdk.listIteratorState(count), 7);
      expect(sdk.listIteratorFinish(), 7);
      expect(native.iteratorState(count), 7);
      expect(native.iteratorFinish(), 7);
    }
  });

  test('constant Lists preserve identity and reject mutation before storage writes', () {
    expect(sdk.listConstantOnly(), 5);
    expect(native.constantOnly(), 5);
    for (final count in [0, 40000]) {
      final expected = count == 0 ? 40 : 41;
      expect(sdk.listConstants(count), expected);
      expect(native.constants(count), expected);
    }
    for (var mode = 0; mode < 5; mode++) {
      final expected = mode == 3 ? 13 : 3;
      expect(sdk.listConstMutation(mode), expected);
      expect(native.constMutation(mode), expected);
    }
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

  test('generic elements, shared fills, cycles and globals survive GC', () {
    for (final count in [0, 10, 40000]) {
      final expected = 69 + count * (count - 1) ~/ 2;
      expect(sdk.listReferences(count), expected);
      expect(native.references(count), expected);
      expect(native.saved(0), 23);
      expect(native.saved(count + 2), count == 0 ? 23 : count - 1);
      expect(sdk.listCycles(count), count == 0 ? 41 : count + 40);
      expect(native.cycles(count), count == 0 ? 41 : count + 40);
    }
  });

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
