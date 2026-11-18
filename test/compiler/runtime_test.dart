@Tags(['assets', 'native'])
library;

import 'dart:ffi';
import 'dart:io';

import 'package:dartc/layout/memory.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  test('compiled heap sizing rounds size classes and failure bounds', () {
    final library = NativeAssets(Target.host()).open('compiler/heap_runtime');
    addTearDown(library.close);
    final capacity = library
        .lookupFunction<Int64 Function(Int64), int Function(int)>('capacity');
    const maximum = 0x1000000000000000;
    for (final (needed, expected) in [
      (0, 0),
      (1, 64),
      (64, 64),
      (65, 128),
      (65536, 65536),
      (65537, 131072),
      (maximum - 1, maximum),
      (maximum, maximum),
      (maximum + 1, 0),
      (-1, 0),
    ]) {
      expect(capacity(needed), expected);
    }
  });

  test(
    'control descriptors trace managed fields and clear weak references',
    () {
      final library = NativeAssets(Target.host()).open('compiler/heap_runtime');
      addTearDown(library.close);
      final createManaged = library
          .lookupFunction<Void Function(Int64), void Function(int)>(
            'createManaged',
          );
      final create = library.lookupFunction<Void Function(), void Function()>(
        'createControl',
      );
      final placement = library
          .lookupFunction<Int64 Function(), int Function()>('controlPlacement');
      final collect = library
          .lookupFunction<Int64 Function(Int64), int Function(int)>(
            'collectPressure',
          );
      final status = library.lookupFunction<Int64 Function(), int Function()>(
        'controlStatus',
      );
      final read = library.lookupFunction<Int64 Function(), int Function()>(
        'readControl',
      );
      final clear = library.lookupFunction<Void Function(), void Function()>(
        'clearControl',
      );
      const count = 20000, sum = count * (count - 1) ~/ 2;
      createManaged(73);
      create();
      expect(placement(), 12, reason: 'The child and closure must be managed.');
      expect(
        status(),
        12,
        reason: 'Both weak targets must exist before pressure.',
      );
      expect(collect(count), sum);
      // A cleared managed witness proves collection, independently of pressure.
      expect(
        status() & 1,
        1,
        reason: 'The collection witness must be cleared.',
      );
      expect(status(), 15);
      expect(read(), 146);
      expect(collect(count), sum);
      expect(status(), 15);
      expect(read(), 146);
      clear();
      expect(
        status() & 3,
        2,
        reason: 'The new collection witness must be present.',
      );
      const finalCount = count * 4;
      expect(collect(finalCount), finalCount * (finalCount - 1) ~/ 2);
      expect(
        status() & 1,
        1,
        reason: 'The new collection witness must be cleared.',
      );
      expect(
        status(),
        11,
        reason: 'Cleared control fields must stop retaining.',
      );
    },
  );

  test('managed allocation remains allowed and observable', () {
    final library = NativeAssets(Target.host()).open('compiler/heap_runtime');
    addTearDown(library.close);
    final create = library
        .lookupFunction<Void Function(Int64), void Function(int)>(
          'createManaged',
        );
    final allocate = library
        .lookupFunction<Void Function(Int64), void Function(int)>(
          'allocateInPhase',
        );
    final value = library.lookupFunction<Int64 Function(), int Function()>(
      'pressureValue',
    );
    create(42);
    allocate(RuntimePhase.managed);
    expect(value(), RuntimePhase.managed);
  });

  for (final (operation, phases) in [
    (
      'entry',
      [
        RuntimePhase.bootstrap,
        RuntimePhase.control,
        RuntimePhase.collecting,
        RuntimePhase.closed,
        -1,
        6,
        0x7fffffffffffffff,
      ],
    ),
    (
      'allocateInPhase',
      [
        RuntimePhase.dormant,
        RuntimePhase.collecting,
        RuntimePhase.closed,
        -1,
        6,
        0x7fffffffffffffff,
      ],
    ),
    (
      'controlInPhase',
      [
        RuntimePhase.dormant,
        RuntimePhase.managed,
        RuntimePhase.collecting,
        RuntimePhase.closed,
        -1,
        6,
        0x7fffffffffffffff,
      ],
    ),
  ]) {
    test(
      '$operation rejects forbidden phases without Dart failure recovery',
      () async {
        for (final phase in phases) {
          final result = await Process.run(Platform.resolvedExecutable, [
            'test/compiler/fixtures/runtime_phase_client.dart',
            operation,
            '$phase',
          ]);
          expect(
            result.exitCode,
            71,
            reason:
                '$operation phase=$phase: ${result.stdout}\n${result.stderr}',
          );
          expect(result.stdout, 'armed\n');
        }
      },
    );
  }
}
