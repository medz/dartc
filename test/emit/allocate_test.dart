import 'package:dartc/lir.dart';
import 'package:dartc/src/emit/allocate.dart';
import 'package:dartc/src/emit/arm64/function.dart';
import 'package:dartc/src/emit/liveness.dart';
import 'package:dartc/src/emit/moves.dart';
import 'package:test/test.dart';

import '../lir/support.dart';
import 'random_lir.dart';

void main() {
  group('liveness', () {
    test('a loop keeps outer values alive to its end', () {
      final entry = LirBlock([.i64, .i64]);
      final loop = LirBlock([.i64]), exit = LirBlock();
      final [outer, count] = entry.parameters;
      entry.end(Jump(LirEdge(loop, [count])));
      final used = loop.add(IntBinary(.add, outer, loop.parameters[0]));
      final next = loop.add(IntBinary(.sub, loop.parameters[0], outer));
      loop.end(Branch(next, LirEdge(loop, [next]), LirEdge(exit)));
      exit.end(Return(used));
      final function = LirFunction('f', LirSignature([.i64, .i64], .i64), [
        entry,
        loop,
        exit,
      ]);
      final intervals = Liveness(function).intervals;
      // Read last near the top of the loop, yet needed by the next iteration.
      expect(intervals[outer]!.end, intervals[next]!.end);
      expect(intervals[count]!.end, lessThan(intervals[used]!.start));
      expect(intervals[used]!.end, greaterThan(intervals[next]!.end));
    });

    test('a block parameter starts at its block', () {
      final entry = LirBlock([.i64]), next = LirBlock([.i64]);
      entry.add(ConstInt(1));
      entry.end(Jump(LirEdge(next, entry.parameters)));
      next.end(Return(next.parameters.single));
      final function = LirFunction('f', LirSignature([.i64], .i64), [
        entry,
        next,
      ]);
      final intervals = Liveness(function).intervals;
      final before = intervals[entry.parameters.single]!;
      final after = intervals[next.parameters.single]!;
      expect(after.start, greaterThan(before.end));
    });

    test('only values needed after a call cross it', () {
      final block = LirBlock([.i64, .i64]);
      final [argument, kept] = block.parameters;
      final signature = LirSignature([.i64], .i64);
      final call = block.add(Call('g', signature, [argument]));
      block.end(Return(block.add(IntBinary(.add, call, kept))));
      final function = LirFunction('f', LirSignature([.i64, .i64], .i64), [
        block,
      ]);
      final intervals = Liveness(function).intervals;
      expect(intervals[argument]!.crossesCall, isFalse);
      expect(intervals[kept]!.crossesCall, isTrue);
      expect(intervals[call]!.crossesCall, isFalse);
    });
  });

  test('registers are reused once their values end', () {
    final made = function('f', [.i64], .i64, (block, p) {
      LirValue value = p[0];
      for (var i = 0; i < 100; i++) {
        value = block.add(IntBinary(.add, value, p[0]));
      }
      return value;
    });
    final allocation = Allocation(Liveness(made), arm64Registers);
    expect(allocation.spillCount, 0);
    expect(allocation.locations.values.toSet(), hasLength(2));
  });

  test('under pressure the value needed last is spilled', () {
    late LirValue longest;
    final made = function('f', [.i64], .i64, (block, p) {
      longest = p[0];
      // One more value than there are registers.
      final values = [for (var i = 0; i < 24; i++) block.add(ConstInt(i))];
      LirValue sum = values.first;
      for (final value in values.skip(1)) {
        sum = block.add(IntBinary(.add, sum, value));
      }
      return block.add(IntBinary(.add, sum, longest));
    });
    final allocation = Allocation(Liveness(made), arm64Registers);
    expect(allocation.spillCount, 1);
    expect(allocation.locations[longest], const OnStack(.spill, 0));
  });

  test('a newcomer needed last is spilled itself', () {
    late LirValue newest;
    final made = function('f', [.i64], .i64, (block, p) {
      final values = [
        p[0],
        for (var i = 0; i < 23; i++) block.add(ConstInt(i)),
      ];
      newest = block.add(ConstInt(99));
      LirValue sum = values.first;
      for (final value in values.skip(1)) {
        sum = block.add(IntBinary(.add, sum, value));
      }
      return block.add(IntBinary(.add, sum, newest));
    });
    final allocation = Allocation(Liveness(made), arm64Registers);
    expect(allocation.spillCount, 1);
    expect(allocation.locations[newest], const OnStack(.spill, 0));
  });

  test('scratch, system and frame registers hold no values', () {
    final values = [...arm64Registers.volatile, ...arm64Registers.preserved];
    expect(values.toSet(), hasLength(values.length));
    final reserved = [...arm64Scratch, 18, 29, 30, 31];
    expect(reserved.toSet(), hasLength(reserved.length));
    expect(values.toSet().intersection(reserved.toSet()), isEmpty);
    // The calling convention fixes which registers survive calls.
    expect(arm64Registers.volatile, everyElement(lessThan(18)));
    expect(arm64Registers.preserved, everyElement(inInclusiveRange(19, 28)));
  });

  test('values alive together never share a location', () {
    var spills = 0, crossings = 0;
    for (var seed = 0; seed < 60; seed++) {
      for (final function in RandomLir(seed).functions()) {
        final liveness = Liveness(function);
        final allocation = Allocation(liveness, arm64Registers);
        spills += allocation.spillCount;
        final intervals = liveness.intervals.values.toList();
        for (final (i, a) in intervals.indexed) {
          final place = allocation.locations[a.value]!;
          if (a.crossesCall) {
            crossings++;
            expect(
              arm64Registers.volatile.map(InRegister.new),
              isNot(contains(place)),
            );
          }
          for (final b in intervals.skip(i + 1)) {
            if (a.start > b.end || b.start > a.end) continue;
            expect(allocation.locations[b.value], isNot(place));
          }
        }
      }
    }
    expect(spills, greaterThan(100));
    expect(crossings, greaterThan(100));
  });

  group('parallel moves', () {
    const temporary = InRegister(99);
    List<Location> places(int count) => [
      for (var i = 0; i < count; i++)
        i.isEven ? InRegister(i) : OnStack(.spill, i),
    ];

    void check(List<int> sources) {
      // Place i receives what place sources[i] held.
      final all = places(6);
      final moves = [
        for (final (i, source) in sources.indexed)
          (source: all[source], destination: all[i]),
      ];
      final content = <Location, int>{for (final (i, p) in all.indexed) p: i};
      for (final move in sequentialize(moves, temporary)) {
        content[move.destination] = content[move.source]!;
      }
      for (final (i, place) in all.indexed) {
        final expected = i < sources.length ? sources[i] : i;
        expect(content[place], expected, reason: '$sources');
      }
    }

    test('every assignment of up to five places', () {
      void enumerate(List<int> prefix) {
        check(prefix);
        if (prefix.length == 5) return;
        for (var source = 0; source < 6; source++) {
          enumerate([...prefix, source]);
        }
      }

      enumerate([]);
    });

    test('two separate cycles', () => check([1, 0, 3, 2, 5, 4]));

    test('moves in place disappear', () {
      expect(
        sequentialize([
          (source: temporary, destination: temporary),
        ], const InRegister(1)),
        isEmpty,
      );
    });
  });
}
