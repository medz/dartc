import 'dart:ffi';

import 'package:dartc/ir.dart';
import 'package:dartc/layout/memory.dart';
import 'package:test/test.dart';

import '../../sdk/runtime/roots.dart';
import '../support/ir_interpreter.dart';
import '../support/runtime.dart';

void main() {
  final allocate = DynamicLibrary.process()
      .lookupFunction<
        Pointer<Int64> Function(Size, Size),
        Pointer<Int64> Function(int, int)
      >('calloc');
  final free = DynamicLibrary.process()
      .lookupFunction<
        Void Function(Pointer<Int64>),
        void Function(Pointer<Int64>)
      >('free');
  late Pointer<Int64> storage;
  late int context, outer, inner, maps, globals;
  final words = (RuntimeContext.size + RuntimeContext.entrySize * 2 + 16) ~/ 8;
  setUpAll(prepareRuntime);
  setUp(() {
    storage = allocate(words, 8);
    if (storage == nullptr) {
      throw StateError('Cannot allocate entry test storage.');
    }
    addTearDown(() => free(storage));
    context = storage.address;
    outer = context + RuntimeContext.size;
    inner = outer + RuntimeContext.entrySize;
    maps = inner + RuntimeContext.entrySize;
    globals = maps + 8;
  });
  Pointer<Int64> word(int address) => Pointer<Int64>.fromAddress(address);
  List<int> snapshot() => List.generate(words, (index) => storage[index]);
  void seed() {
    for (var index = 0; index < words; index++) {
      storage[index] = index + 100;
    }
    word(context + RuntimeContext.active).value = 0;
    word(globals + ModuleRootTable.count).value = 0;
  }

  test('ordinary entry bodies preserve nested roots and context lifetime', () {
    seed();
    word(context + RuntimeContext.phase).value = RuntimePhase.dormant;
    final before = snapshot();
    NativeRoots.link(context, outer, maps, globals);
    expect(word(outer + RuntimeContext.previousEntry).value, 0);
    expect(word(outer + RuntimeContext.suspendedSp).value, 0);
    expect(word(outer + RuntimeContext.suspendedPc).value, 0);
    expect(word(context + RuntimeContext.active).value, outer);
    expect(word(context + RuntimeContext.maps).value, maps);
    expect(word(context + RuntimeContext.globalRoots).value, globals);
    for (final offset in [
      RuntimeContext.heap,
      RuntimeContext.bootstrap,
      RuntimeContext.phase,
      RuntimeContext.controlCursor,
      RuntimeContext.controlLimit,
    ]) {
      expect(word(context + offset).value, before[offset ~/ 8]);
    }

    word(context + RuntimeContext.phase).value = RuntimePhase.managed;
    word(outer + RuntimeContext.suspendedSp).value = 123;
    word(outer + RuntimeContext.suspendedPc).value = 456;
    NativeRoots.link(context, inner, maps, globals);
    expect(word(inner + RuntimeContext.previousEntry).value, outer);
    expect(word(inner + RuntimeContext.suspendedSp).value, 0);
    expect(word(inner + RuntimeContext.suspendedPc).value, 0);
    expect(word(context + RuntimeContext.active).value, inner);
    NativeRoots.unlink(context, inner);
    expect(word(context + RuntimeContext.active).value, outer);
    expect(word(outer + RuntimeContext.suspendedSp).value, 123);
    expect(word(outer + RuntimeContext.suspendedPc).value, 456);

    // Release returns a reusable context to dormant before the entry unlinks.
    word(context + RuntimeContext.phase).value = RuntimePhase.dormant;
    NativeRoots.unlink(context, outer);
    expect(word(context + RuntimeContext.active).value, 0);
    expect(word(context + RuntimeContext.maps).value, maps);
    expect(word(context + RuntimeContext.globalRoots).value, globals);
    expect(
      word(context + RuntimeContext.heap).value,
      before[RuntimeContext.heap ~/ 8],
    );
  });

  // Only the terminating machine leaf is replaced by a throwing model. The
  // actual lowered runtime bodies perform all guards, native loads and stores.
  // This establishes fail-before-mutation, not native process termination.
  IrInterpreter interpreter(void Function() fail) => IrInterpreter(
    heapRuntime.program,
    {},
    externalCalls: {
      heapRuntime.primitives.entries
          .singleWhere((entry) => entry.value == .fail)
          .key: (_) =>
          fail(),
    },
  );

  test('entry rejects every disallowed phase before touching storage', () {
    var failures = 0;
    final failure = StateError('modeled fatal entry rejection');
    final model = interpreter(() {
      failures++;
      throw failure;
    });
    final link = heapRuntime.program.implementationOf(
      heapRuntime.linkEntry,
    ) as IrFunction;
    for (final phase in [
      RuntimePhase.bootstrap,
      RuntimePhase.control,
      RuntimePhase.collecting,
      RuntimePhase.closed,
      -1,
      6,
      -0x8000000000000000,
      0x7fffffffffffffff,
    ]) {
      seed();
      word(context + RuntimeContext.phase).value = phase;
      final before = snapshot();
      final previousFailures = failures;
      expect(
        () => model.run(link, [context, outer, maps, globals]),
        throwsA(same(failure)),
        reason: 'phase $phase',
      );
      expect(failures, previousFailures + 1);
      expect(snapshot(), before, reason: 'phase $phase');
    }
  });

  test('out-of-order unlink fails without corrupting the active chain', () {
    NativeRoots.link(context, outer, maps, globals);
    NativeRoots.link(context, inner, maps, globals);
    final before = snapshot();
    final failure = StateError('modeled fatal unlink rejection');
    final model = interpreter(() => throw failure);
    final unlink = heapRuntime.program.implementationOf(
      heapRuntime.unlinkEntry,
    ) as IrFunction;
    expect(() => model.run(unlink, [context, outer]), throwsA(same(failure)));
    expect(snapshot(), before);
    NativeRoots.unlink(context, inner);
    NativeRoots.unlink(context, outer);
    expect(word(context + RuntimeContext.active).value, 0);
  });
}
