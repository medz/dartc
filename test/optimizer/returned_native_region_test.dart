import 'dart:ffi' show Int64;

import 'package:dartc/abi.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/src/optimizer/flow_state.dart';
import 'package:dartc/src/optimizer/flow_value.dart' show FlowRegion;
import 'package:dartc/target.dart';
import 'package:test/test.dart';

final word = NativeScalarType(Int64);

final class _Layout() implements FlowMemoryLayout {
  @override
  final nativeLayout = NativeLayout(const Target(.linux, .x64));
  @override
  ObjectLayout objectLayout(ClassType type) => ObjectLayout([]);
}

void main() {
  for (final releasePrevious in [false, true]) {
    test(
      'a newly released mapping and a published mapping survive re-entry (release previous=$releasePrevious)',
      () {
        final uri = Uri.parse('memory:reused-native-allocation');
        final slots = NativeData(List.filled(24, 0), alignment: 8);
        final map = FunctionTarget(uri, 'map', .integer, [.integer]),
            free = FunctionTarget(uri, 'free', .voidType, [.integer, .integer]);
        final worker = FunctionTarget(uri, 'worker', .voidType, [.boolean]),
            root = FunctionTarget(uri, 'root', .integer, [.boolean]);
        final make = Block(worker.parameterTypes),
            split = Block(),
            publish = Block(),
            discard = Block(),
            done = Block(),
            releaseOld = Block(),
            failed = Block();
        final pair = make.emit(NativeDataAddress(slots)),
            second = make.emit(
              IntBinary(.add, pair, const Constant.integer(8)),
            ),
            p = make.emit(DirectCall(map, [const Constant.integer(16)]));
        make.finish(
          Branch(
            make.emit(Equals(p, const Constant.integer(0))),
            Jump(done),
            Jump(split),
          ),
        );
        split.finish(
          Branch(make.parameters.single, Jump(publish), Jump(discard)),
        );
        publish.emit(StoreNative(pair, word, p));
        publish.finish(Jump(done));
        discard.emit(StoreNative(second, word, p));
        discard.emit(DirectCall(free, [p, const Constant.integer(16)]));
        final previous = discard.emit(LoadNative(pair, word));
        DirectCall? explicitRelease;
        if (releasePrevious) {
          discard.emit(
            StoreNative(
              discard.emit(IntBinary(.add, pair, const Constant.integer(16))),
              word,
              previous,
            ),
          );
          discard.emit(StoreNative(pair, word, const Constant.integer(0)));
          discard.finish(
            Branch(
              discard.emit(Equals(previous, const Constant.integer(0))),
              Jump(failed),
              Jump(releaseOld),
            ),
          );
          explicitRelease = releaseOld.emit(
            DirectCall(free, [previous, const Constant.integer(16)]),
          );
          releaseOld.finish(Jump(failed));
        } else {
          discard.finish(Jump(failed));
        }
        failed.finish(Throw(const Constant.string('error')));
        done.finish(const Return());
        final start = Block(root.parameterTypes),
            ordinary = Block(),
            caught = Block(),
            read = Block();
        final call = DirectCall(worker, start.parameters);
        start.finish(
          Invoke(call, onReturn: Jump(ordinary), onThrow: Jump(caught)),
        );
        ordinary.finish(const Return(Constant.integer(-1)));
        final ctx = caught.emit(NativeDataAddress(slots)),
            old = caught.emit(
              LoadNative(
                releasePrevious
                    ? caught.emit(
                        IntBinary(.add, ctx, const Constant.integer(16)),
                      )
                    : ctx,
                word,
              ),
            );
        caught.finish(
          Branch(
            caught.emit(Equals(old, const Constant.integer(0))),
            Jump(ordinary),
            Jump(read),
          ),
        );
        final live = read.emit(IntBinary(.add, old, const Constant.integer(0)));
        final dead = read.emit(
          LoadNative(
            read.emit(IntBinary(.add, ctx, const Constant.integer(8))),
            word,
          ),
        );
        final point = read.emit(KeepAlive(live));
        read.finish(Return(dead));
        final graph = IrProgram(
          [],
          [
            IrFunction(root, [start, ordinary, caught, read]),
            IrFunction(worker, [
              make,
              split,
              publish,
              discard,
              done,
              if (releasePrevious) releaseOld,
              failed,
            ]),
          ],
          externals: [
            IrExternal(
              map,
              effects: {},
              memory: const ExternalMemory.zeroed(0),
            ),
            IrExternal(
              free,
              effects: {Effect.writesStorage},
              memory: const ExternalMemory.release(0, 1),
            ),
          ],
        );
        final facts = ProgramFlow(
          graph,
          [],
          openEntries: [root],
          memoryLayout: _Layout(),
        ).facts;
        final state = facts.pointStateOf(point)!.before;
        final owners = facts.valueOf(live).addresses,
            temporary = facts.valueOf(dead).addresses;
        expect(facts.activationsOf(worker), hasLength(1));
        if (!releasePrevious) {
          // This open entry can be called successively. Its published slot
          // observes both its initial and later successful allocations.
          expect(owners, hasLength(2));
          expect(temporary, isNotEmpty);
          expect(facts.valueOf(live).unknownTypes, isEmpty);
          expect(facts.valueOf(dead).unknownTypes, isEmpty);
          expect(owners.any(temporary.contains), isFalse);
          expect(
            owners.every(
              (a) => state.containsNative(FlowValue.address(a), word),
            ),
            isTrue,
          );
        } else {
          expect(facts.reachesOperation(explicitRelease!), isTrue);
          expect(state.containsNative(facts.valueOf(live), word), isFalse);
          expect(state.containsNative(facts.valueOf(dead), word), isFalse);
        }
        expect(
          temporary.every(
            (a) => !state.containsNative(FlowValue.address(a), word),
          ),
          isTrue,
        );
      },
    );
  }
  final graph = IrProgram([], []);
  final layout = _Layout();
  final site = DirectCall(
    FunctionTarget(Uri.parse('memory:test'), 'map', .integer, []),
    [],
  );
  FlowValue n(int value) => FlowValue.constant(Constant.integer(value));
  FlowValue pointer(FlowObject region) =>
      FlowValue.address(FlowAddress(FlowRegion(region), 0));
  FlowState allocate(FlowState state, FlowObject region, FlowValue size) =>
      state.allocateMemory(region, size, repeated: false).normal!;
  FlowResult step(
    FlowState state,
    Instruction operation,
    List<FlowValue> args,
  ) => state.transfer(
    operation,
    args,
    allocate: (_) => throw StateError('allocate'),
    repeated: false,
    invoke: (_, _, _) => throw StateError('invoke'),
    call: (_, _, _) => throw StateError('call'),
  )!;
  const zero = Constant.integer(0);
  FlowState store(FlowState s, FlowObject object, int value) => step(
    s,
    StoreNative(zero, word, zero),
    [pointer(object), n(value)],
  ).normal!;
  FlowValue load(FlowState s, FlowObject object) =>
      step(s, LoadNative(zero, word), [pointer(object)]).value;
  FlowState apply(
    FlowState caller,
    FlowState entry,
    FlowState exit,
    FlowObject Function(FlowObject) rename,
  ) => caller.applySummary(
    entry,
    exit,
    mapObject: rename,
    mapValue: (v) => v.mapObjects(rename),
  );

  test('joining an equivalent native-only input reaches a fixed point', () {
    final original = FlowObject(site, Object()), renamed = FlowObject(site, Object());
    final start = allocate(FlowState(graph, memoryLayout: layout), original, n(16));
    final left = start.mapObjects({original: renamed});
    final right = start.mapObjects({original: renamed});
    expect(left, right);
    expect(left.join(right), isFalse);
    final written = store(right, renamed, 92);
    expect(left.join(written), isTrue);
    final possible = load(left, renamed).integers!;
    expect(possible.contains(0), isTrue);
    expect(possible.contains(92), isTrue);
    expect(left.join(written), isFalse);
  });

  for (final reverse in [false, true]) {
    test(
      'multiple fresh mappings sharing a bounded name weakly merge (reverse=$reverse)',
      () {
        final existing = FlowObject(site, Object());
        var caller = store(
          allocate(FlowState(graph, memoryLayout: layout), existing, n(16)),
          existing,
          17,
        );
        // Each round is a new invocation, with two fresh, individually written
        // mappings escaping into a name that already denotes a previous mapping.
        for (var round = 0; round < 9; round++) {
          final entry = caller.copy(resetWrites: true);
          var exit = entry;
          for (final value in reverse ? [91, 43] : [43, 91]) {
            final raw = FlowObject(site, Object());
            exit = store(allocate(exit, raw, n(16)), raw, value);
          }
          caller = apply(caller, entry, exit, (_) => existing);
          expect(caller.allocations, hasLength(1));
          final values = load(caller, existing);
          for (final value in [17, 43, 91]) {
            expect(values.integers!.contains(value), isTrue);
          }
          // A write to one of the concrete mappings cannot kill the others.
          caller = store(caller, existing, 63);
          final valuesAfter = load(caller, existing);
          expect(valuesAfter.integers!.contains(17), isTrue);
          expect(valuesAfter.integers!.contains(91), isTrue);
        }
      },
    );
  }
  test('an exit computed with a singleton input preserves later occupants', () {
    final name = FlowObject(site, Object());
    final one = store(
      allocate(FlowState(graph, memoryLayout: layout), name, n(16)),
      name,
      17,
    );
    final entry = one.copy(resetWrites: true);
    final exit = store(entry, name, 91);
    final alreadyShared = one
        .allocateMemory(name, n(16), repeated: true)
        .normal!;
    final returned = apply(alreadyShared, entry, exit, (o) => o);
    final actual = load(returned, name);
    expect(actual.integers!.contains(17), isTrue);
    expect(actual.integers!.contains(91), isTrue);
  });
  for (final released in [false, true]) {
    test(
      'a stale singleton exit preserves later bytes or release (released=$released)',
      () {
        final name = FlowObject(site, Object());
        final first = allocate(
          FlowState(graph, memoryLayout: layout),
          name,
          n(16),
        );
        final entry = first.copy(resetWrites: true);
        final exit = store(entry, name, 91);
        final other = FlowValue.address(FlowAddress(FlowRegion(name), 8));
        final changed = step(first, StoreNative(zero, word, zero), [
          other,
          n(1234),
        ]).normal!;
        final caller = released
            ? changed.overwriteNative(pointer(name), n(16), release: true)
            : changed;
        final result = apply(caller, entry, exit, (o) => o);
        if (released) {
          expect(result.isMappedAddress(pointer(name)), isFalse);
          expect(result.regionSawRelease(name), isTrue);
        } else {
          expect(
            step(result, LoadNative(zero, word), [
              other,
            ]).value.integers!.contains(1234),
            isTrue,
          );
          // Replaying state did not allocate a second concrete object.
          final overwritten = store(result, name, 72);
          expect(load(overwritten, name).integers!.constant, 72);
        }
      },
    );
  }
  for (final released in [false, true]) {
    test(
      'replaying a summary preserves a later occupant (released=$released)',
      () {
        final name = FlowObject(site, Object());
        final begin = FlowState(graph, memoryLayout: layout);
        final shared = store(
          begin.allocateMemory(name, n(16), repeated: true).normal!,
          name,
          17,
        );
        final entry = shared.copy(resetWrites: true);
        final exit = store(entry, name, 91);
        final grown = store(
          shared.allocateMemory(name, n(16), repeated: true).normal!,
          name,
          1234,
        );
        final caller = released
            ? grown.overwriteNative(pointer(name), n(16), release: true)
            : grown;
        final next = apply(caller, entry, exit, (o) => o);
        if (released) {
          expect(next.isMappedAddress(pointer(name)), isFalse);
          expect(next.regionSawRelease(name), isTrue);
        } else {
          final values = load(next, name);
          expect(values.integers!.contains(1234), isTrue);
          expect(values.integers!.contains(91), isTrue);
        }
      },
    );
  }

  test(
    'a release at either of two bounded offsets revokes the mapping guarantee',
    () {
      final region = FlowObject(site, Object()),
          other = FlowObject(site, Object());
      final state = allocate(
        allocate(FlowState(graph, memoryLayout: layout), region, n(32)),
        other,
        n(32),
      );
      final address = FlowValue.address(
        FlowAddress.ranged(
          FlowRegion(region),
          FlowIntegerRange(0, 8, strideBits: 3, residue: 0),
        ),
      );
      final released = state.overwriteNative(address, n(8), release: true);
      expect(released.containsNative(pointer(region), word), isFalse);
      expect(released.regionSawRelease(region), isTrue);
      expect(released.containsNative(pointer(other), word), isTrue);
    },
  );
  test('partial releases keep references in surviving bytes', () {
    final region = FlowObject(site, Object()),
        pointed = FlowObject(site, Object());
    final state = allocate(
      allocate(FlowState(graph, memoryLayout: layout), region, n(32)),
      pointed,
      n(16),
    );
    final savedAt = FlowValue.address(FlowAddress(FlowRegion(region), 16));
    final stored = step(state, StoreNative(zero, word, zero), [
      savedAt,
      pointer(pointed),
    ]).normal!;
    for (final size in [4, 32]) {
      final released = stored.overwriteNative(
        pointer(region),
        n(size),
        release: true,
      );
      expect(released.isMappedAddress(pointer(region)), isFalse);
      expect(
        released.project([pointer(region)]).containsObject(pointed),
        size < 32,
      );
    }
  });
  test('releasing a shared prefix retains a pointer in a longer mapping', () {
    final region = FlowObject(site, Object());
    final pointee = FlowObject(site, Object());
    final entry = allocate(FlowState(graph, memoryLayout: layout), pointee, n(16));
    final short = allocate(entry, region, n(16384));
    final long = allocate(entry, region, n(32768));
    final tail = FlowValue.address(FlowAddress(FlowRegion(region), 16384));
    final stored = step(long, StoreNative(zero, word, zero), [tail, pointer(pointee)]).normal!;
    final both = short.copy()..join(stored);
    expect(both.project([pointer(region)]).containsObject(pointee), isTrue);
    final rest = both.overwriteNative(pointer(region), n(16384), release: true);
    expect(rest.isMappedAddress(pointer(region)), isFalse);
    expect(rest.project([pointer(region)]).containsObject(pointee), isTrue);
    final full = stored.overwriteNative(pointer(region), n(32768), release: true);
    expect(full.project([pointer(region)]).containsObject(pointee), isFalse);
  });

  test('the common prefix of a ranged mapping has a bounded write', () {
    final region = FlowObject(site, Object()), other = FlowObject(site, Object());
    final entry = store(allocate(FlowState(graph, memoryLayout: layout), other, n(16)), other, 1009);
    final both = allocate(entry, region, FlowValue.integerRange(FlowIntegerRange(16384, 32768)));
    final last = FlowValue.address(FlowAddress(FlowRegion(region), 16376));
    final tail = FlowValue.address(FlowAddress(FlowRegion(region), 16384));
    expect(both.containsNative(last, word), isTrue);
    expect(both.containsNative(tail, word), isFalse);
    final changed = step(both, StoreNative(zero, word, zero), [last, n(37)]).normal!;
    expect(load(changed, other).integers?.constant, 1009);
    expect(step(changed, LoadNative(zero, word), [last]).value.integers?.constant, 37);
  });

  test('a release with an unknown target revokes every possible extent', () {
    final old = FlowObject(site, Object()), other = FlowObject(site, Object());
    final begin = allocate(
      allocate(FlowState(graph, memoryLayout: layout), old, n(16)),
      other,
      n(16),
    );
    final state = step(begin, StoreNative(zero, word, zero), [
      pointer(old),
      pointer(other),
    ]).normal!;
    final afterWrite = state.overwriteNative(
      FlowValue.unknown(.integer),
      n(16),
    );
    expect(afterWrite.containsNative(pointer(old), word), isTrue);
    expect(afterWrite.containsNative(pointer(other), word), isTrue);
    final freed = state.overwriteNative(
      FlowValue.unknown(.integer),
      n(16),
      release: true,
    );
    for (final object in [old, other]) {
      expect(freed.regionSawRelease(object), isTrue);
      expect(freed.containsNative(pointer(object), word), isFalse);
      expect(freed.isMappedAddress(pointer(object)), isFalse);
    }
    // The unknown call may leave old intact, and the other mapping remains
    // reachable through the bytes it held.
    expect(freed.project([pointer(old)]).regionSawRelease(other), isTrue);
  });
  test('an input mapping can be released while an escaping fresh mapping stays live', () {
    final old = FlowObject(site, Object()), fresh = FlowObject(site, Object());
    final caller = allocate(FlowState(graph, memoryLayout: layout), old, n(16));
    final entry = caller.copy(resetWrites: true);
    final exit = allocate(
      entry,
      fresh,
      n(16),
    ).overwriteNative(pointer(old), n(16), release: true);
    final rebound = FlowObject(site, Object());
    final returned = apply(
      caller,
      entry,
      exit,
      (o) => o == fresh ? rebound : o,
    );
    expect(returned.containsNative(pointer(old), word), isFalse);
    expect(returned.regionSawRelease(old), isTrue);
    expect(returned.containsNative(pointer(rebound), word), isTrue);
    expect(returned.regionSawRelease(rebound), isFalse);
  });
  test('unobservable scratch disappears while unknown extents and zero-length unmaps retain their meaning', () {
    final scratch = FlowObject(site, Object());
    final entry = FlowState(graph, memoryLayout: layout);
    final allocated = allocate(entry, scratch, FlowValue.unknown(.integer));
    expect(allocated.containsNative(pointer(scratch), word), isFalse);
    expect(allocated.regionSawRelease(scratch), isFalse);
    final noop = allocated.overwriteNative(
      pointer(scratch),
      n(0),
      release: true,
    );
    expect(noop.regionSawRelease(scratch), isFalse);
    final freed = noop.overwriteNative(pointer(scratch), n(16), release: true);
    expect(freed.regionSawRelease(scratch), isTrue);
    final projected = freed.project([]);
    final returned = apply(entry, entry, projected, (o) => o);
    expect(returned.allocations, isEmpty);
    expect(returned.regionSawRelease(scratch), isNull);
  });
}
