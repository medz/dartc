import 'dart:math';

import 'package:dartc/heap.dart';
import 'package:test/test.dart';

import 'simulated.dart';

late SimulatedMachine _machine;

void _start({bool collectsAlways = false, int available = 1 << 40}) {
  _machine = SimulatedMachine(
    collectsAlways: collectsAlways,
    available: available,
  );
  machine = _machine;
  program = SimulatedProgram();
  heap = 0;
}

/// A new object of a class, as compiled code creates it.
int _create(int class_) {
  final object = allocate(sizes[class_]);
  _machine.store32(object, class_);
  return object;
}

/// A new object of a weak class, whose fields are [values] by their offsets.
int _createWeak(int kind, Map<int, int> values) {
  final object = allocate(80);
  _machine.store32(object, classes.length + kind);
  values.forEach((offset, value) => _machine.store64(object + offset, value));
  return object;
}

int _load(int object, int offset) => _machine.load64(object + offset);

void _weakTests() {
  test('references are cleared when their targets are gone', () {
    final kept = _create(0), dropped = _create(0);
    final weak = [
      for (final target in [kept, dropped, 0, 7]) _createWeak(0, {8: target}),
    ];
    _machine.frames.add([kept, weak[0], weak[1], weak[2], weak[3]]);
    for (var i = 0; i < 3; i++) {
      collect();
      expect([for (final one in weak) _load(one, 8)], [kept, 0, 0, 7]);
      expect([for (final one in weak) _load(one, 16)], everyElement(0));
    }
  });

  test('properties keep their values as long as their keys', () {
    final keys = [for (var i = 0; i < 4; i++) _create(0)];
    final other = _create(0), value = _create(0);
    // A chain, in both orders, and one whose key only it has.
    final weak = [
      _createWeak(1, {8: keys[2], 16: keys[3]}),
      _createWeak(1, {8: keys[0], 16: keys[1]}),
      _createWeak(1, {8: keys[1], 16: keys[2]}),
      _createWeak(1, {8: other, 16: other}),
    ];
    _machine
      ..frames.add([keys[0], weak[0], weak[1], weak[2], weak[3]])
      ..setGlobal(0, _createWeak(1, {8: keys[3], 16: value}));
    for (var i = 0; i < 3; i++) {
      collect();
      expect(_load(weak[0], 16), keys[3]);
      expect(_load(weak[3], 8), 0);
      expect(_load(weak[3], 16), 0);
      expect(_load(_machine.global(0), 16), value);
      expect(_machine.load32(value + 4), isNot(0));
    }
    _machine.frames.single[0] = 0;
    collect();
    expect([for (final one in weak) _load(one, 16)], everyElement(0));
    expect(_load(_machine.global(0), 16), 0);
  });

  test('entries are queued when their values are gone', () {
    final kept = _create(0), dropped = _create(0), token = _create(0);
    final finalizer = _create(0), queue = _createWeak(3, {});
    int entry(int value) => _createWeak(2, {
      8: token,
      24: value,
      32: value,
      40: finalizer,
      48: 123,
      56: 456,
      64: 1000,
    });
    final entries = [entry(kept), entry(dropped), entry(dropped)];
    _machine.frames.add([queue, ...entries, kept]);
    _machine.setGlobal(0, finalizer);
    countOutside(3000);
    collect();
    expect(_load(entries[0], 24), kept);
    expect(_load(entries[0], 64), 1000);
    final queued = <int>[];
    for (var at = firstEntry(); at != 0; at = nextEntry(at)) {
      queued.add(at);
      expect(_load(at, 8), token);
      expect(_load(at, 24), 0);
      expect(_load(at, 32), 0);
      expect(_load(at, 40), finalizer);
      expect(_load(at, 64), 0);
      expect(_machine.load64(entryFunction(at)), 123);
      expect(_machine.load64(entryArgument(at)), 456);
    }
    expect(queued, unorderedEquals([entries[1], entries[2]]));
    // They are not queued again.
    collect();
    expect(firstEntry(), queued[0]);
    expect(nextEntry(queued[0]), queued[1]);
    expect(nextEntry(queued[1]), 0);
    _machine.setGlobal(0, 0);
    collect();
    expect(_load(entries[0], 40), 0);
  });

  test('what objects stand for outside starts collections', () {
    _create(0);
    final before = _machine.collections;
    countOutside(5 << 20);
    for (var i = 0; i < 20000; i++) {
      _create(0);
    }
    expect(_machine.collections, greaterThan(before));
  });
}

void main() {
  setUp(_start);

  group('weak', _weakTests);

  group('allocation', () {
    test('gives separate, aligned, zeroed memory', () {
      final found = <int, int>{};
      for (final bytes in [
        ...[8, 16, 17, 24, 100, 512, 513, 640, 641, 1024, 1025, 5000],
        ...[32767, 32768, 32769, 300000],
      ]) {
        for (var i = 0; i < 20; i++) {
          final object = allocate(bytes);
          expect(object % 16, 0);
          expect(_machine.load32(object), 0);
          for (var at = 8; at + 8 <= bytes; at += 8) {
            expect(_machine.load64(object + at), 0);
            _machine.store64(object + at, -1);
          }
          found.forEach((other, length) {
            expect(object + bytes <= other || other + length <= object, isTrue);
          });
          found[object] = bytes;
        }
      }
    });

    // All that is asked for is kept.
    for (final bytes in [528, 640, 648, 1000, 5000, 20000, 32768]) {
      test('gives objects of $bytes bytes shared blocks', () {
        final before = (_machine.mapped, _machine.mappings);
        const count = 300;
        for (var i = 0; i < count; i++) {
          final object = allocate(bytes);
          _machine.store64(object + bytes - 8, -1);
          _machine.frames.add([object]);
        }
        final (mapped, mappings) = before;
        expect(_machine.mappings - mappings, lessThan(count ~/ 5));
        // A quarter more, and the last block.
        expect(
          _machine.mapped - mapped,
          lessThan(count * bytes * 5 ~/ 4 + (1 << 19)),
        );
      });
    }

    test('gives 0 where there is no memory', () {
      _start(available: 1 << 21);
      _machine.frames.add([0]);
      int fill() {
        var count = 0;
        for (var list = 0; ; count++) {
          final object = allocate(sizes[1]);
          if (object == 0) return count;
          _machine
            ..store32(object, 1)
            ..store64(object + 8, list);
          list = _machine.frames.last[0] = object;
        }
      }

      final count = fill();
      expect(count, greaterThan(1 << 16));
      expect(allocate(16), 0);
      expect(allocate(1 << 22), 0);
      // The program is told each time, as compiled programs throw then.
      expect((program as SimulatedProgram).exhaustions, 3);
      // All kept objects are whole.
      var found = 0;
      for (
        var at = _machine.frames.last[0];
        at != 0;
        at = _machine.load64(at + 8)
      ) {
        found++;
      }
      expect(found, count);
      // What is dropped can be used again, at once.
      _machine.frames.last[0] = 0;
      expect(fill(), count);
    });

    test('gives 0 until there is memory to start with', () {
      for (final available in [0, 1500, 60000]) {
        _start(available: SimulatedMachine.ownBytes + available);
        expect(allocate(16), 0);
        expect(allocate(16), 0);
        expect((program as SimulatedProgram).exhaustions, 2);
        expect(heap, 0);
        expect(_machine.mapped, SimulatedMachine.ownBytes);
      }
    });

    test('collects before it gives up', () {
      _start(available: 1 << 20);
      for (var i = 0; i < 1 << 16; i++) {
        expect(allocate(64), isNot(0));
      }
      expect(_machine.collections, greaterThan(2));
    });
  });

  group('collection', () {
    test('reuses the memory of unreachable objects', () {
      for (var i = 0; i < 400000; i++) {
        _create(1);
      }
      // 6.4 MB were allocated in all.
      expect(_machine.mostMapped, lessThan(6 << 20));
    });

    test('frees large objects', () {
      for (var i = 0; i < 100; i++) {
        allocate(1 << 20);
      }
      expect(_machine.mostMapped, lessThan(12 << 20));
      collect();
      expect(_machine.mapped, lessThan(1 << 20));
    });

    test('keeps what each kind of root reaches', () {
      final objects = [for (var i = 0; i < 8; i++) _create(1)];
      for (var i = 0; i + 1 < 4; i++) {
        _machine.store64(objects[i] + 8, objects[i + 1]);
      }
      _machine.frames.addAll([
        [objects[0]],
        [],
        [0, objects[4]],
      ]);
      _machine.setGlobal(3, objects[5]);
      collect();
      expect(_isAllocated(objects[6]), isFalse);
      expect(_isAllocated(objects[7]), isFalse);
      for (final kept in objects.take(6)) {
        expect(_isAllocated(kept), isTrue);
        expect(_machine.load32(kept), 1);
      }
      _machine.frames.removeAt(0);
      collect();
      expect(objects.take(6).map(_isAllocated), [
        false,
        false,
        false,
        false,
        true,
        true,
      ]);
    });

    test('follows cycles and long chains', () {
      var list = 0;
      for (var i = 0; i < 100000; i++) {
        final object = _create(1);
        _machine.store64(object + 8, list);
        list = object;
        if (_machine.frames.isEmpty) {
          _machine.frames.add([list]);
        }
        _machine.frames.last[0] = list;
      }
      var first = list;
      while (_machine.load64(first + 8) != 0) {
        first = _machine.load64(first + 8);
      }
      _machine.store64(first + 8, list);
      collect();
      var count = 0, at = list;
      do {
        expect(_isAllocated(at), isTrue);
        at = _machine.load64(at + 8);
        count++;
      } while (at != list);
      expect(count, 100000);
    });

    test('follows the elements of arrays', () {
      final array = allocate(24 + 5 * 8);
      _machine
        ..store32(array, arrayClass)
        ..store64(array + 16, 5)
        ..setGlobal(0, array);
      final [field, lost, ...elements] = [
        for (var i = 0; i < 6; i++) _create(0),
      ];
      _machine.store64(array + 8, field);
      for (final (i, element) in elements.indexed) {
        _machine.store64(array + 24 + i * 8, element);
      }
      collect();
      expect(_isAllocated(lost), isFalse);
      for (final kept in [field, ...elements]) {
        expect(_isAllocated(kept), isTrue);
      }
    });

    test('follows many references at once', () {
      // Each object of the chain leaves two others to be scanned later.
      const length = 20000;
      _machine.frames.add([0]);
      var list = 0;
      for (var i = 0; i < length; i++) {
        final object = _create(2);
        _machine
          ..store64(object + 24, list)
          ..frames.last[0] = object;
        for (final offset in [8, 16]) {
          final leaf = _create(1);
          _machine.store64(object + offset, leaf);
        }
        list = object;
      }
      final before = _machine.mapped;
      collect();
      collect();
      // The memory that held fewer of them is given back.
      expect(_machine.mapped - before, lessThan(length * 2 * 8 * 2));
      for (var at = list; at != 0; at = _machine.load64(at + 24)) {
        expect(_isAllocated(at), isTrue);
        for (final offset in [8, 16]) {
          final leaf = _machine.load64(at + offset);
          expect(_isAllocated(leaf), isTrue);
          expect(_machine.load64(leaf + 8), 0);
        }
      }
    });

    // As above, where a few or many of them do not fit.
    for (final length in [4200, 12000]) {
      test('follows $length references without memory to remember them', () {
        _start();
        _machine.frames.add([0]);
        var list = 0;
        for (var i = 0; i < length; i++) {
          final object = _create(2);
          _machine
            ..store64(object + 24, list)
            ..frames.last[0] = object;
          for (final offset in [8, 16]) {
            // Links to later and to earlier cells.
            final chain = [for (var j = 0; j < 4; j++) _create(1)];
            final order = offset == 8 ? chain : chain.reversed.toList();
            for (var j = 0; j < 3; j++) {
              _machine.store64(order[j] + 8, order[j + 1]);
            }
            _machine.store64(object + offset, order.first);
          }
          list = object;
        }
        final lost = [_create(1), _create(1)];
        _machine.store64(lost[0] + 8, lost[1]);
        _machine.available = _machine.mapped;
        collect();
        for (var at = list; at != 0; at = _machine.load64(at + 24)) {
          expect(_isAllocated(at), isTrue);
          for (final offset in [8, 16]) {
            var links = 0;
            for (
              var link = _machine.load64(at + offset);
              link != 0;
              link = _machine.load64(link + 8)
            ) {
              expect(_isAllocated(link), isTrue);
              links++;
            }
            expect(links, 4);
          }
        }
        expect(lost.map(_isAllocated), [false, false]);
        _machine.frames.last[0] = 0;
        collect();
        expect(_isAllocated(list), isFalse);
      });
    }

    test('keeps cells of every size apart', () {
      final sizes = [
        for (var bytes = 8; bytes <= 600; bytes += 8) bytes,
        for (var bytes = 608; bytes <= 40000; bytes += bytes ~/ 128 * 8) bytes,
      ];
      for (final bytes in sizes) {
        final kept = allocate(bytes);
        _machine.frames.add([kept]);
        allocate(bytes);
      }
      for (var round = 0; round < 3; round++) {
        collect();
        final given = {for (final frame in _machine.frames) frame.single};
        for (final bytes in sizes) {
          for (var i = 0; i < 3; i++) {
            final object = allocate(bytes);
            expect(given.add(object), isTrue);
            for (var at = 8; at + 8 <= bytes; at += 8) {
              expect(_machine.load64(object + at), 0);
              _machine.store64(object + at, -1);
            }
          }
        }
      }
    });

    test('gives each free cell once', () {
      for (final bytes in [16, 496, 512, 528, 5120, 20000, 32768]) {
        _start();
        final given = {allocate(bytes)};
        _machine.frames.add([given.first]);
        allocate(bytes);
        collect();
        // More than one block has.
        final count = 262144 ~/ bytes + 10;
        for (var i = 0; i < count; i++) {
          expect(given.add(allocate(bytes)), isTrue);
        }
      }
    });

    test('happens less often the more is kept', () {
      int collections(int objects) {
        _start();
        _machine.frames.add([0]);
        for (var list = 0, i = 0; i < objects; i++) {
          final object = _create(2);
          _machine.store64(object + 8, list);
          _machine.frames.last[0] = list = object;
        }
        return _machine.collections;
      }

      // 4 MB each until that much is kept, then as much as is kept.
      expect(collections(100000), 0);
      expect(collections(150000), 1);
      expect(collections(240000), 1);
      expect(collections(1000000), inInclusiveRange(2, 3));
    });

    test('leaves objects that were there from the start alone', () {
      final static_ = _machine.mapMemory(32);
      _machine
        ..store32(static_, 2)
        ..store32(static_ + 4, 4)
        ..store64(static_ + 8, 12345);
      final holder = _create(1);
      _machine
        ..store64(holder + 8, static_)
        ..frames.add([holder, static_]);
      collect();
      expect(_machine.load32(static_ + 4), 4);
      expect(_isAllocated(holder), isTrue);
    });

    test('happens on every allocation when asked', () {
      _start(collectsAlways: true);
      final kept = _create(1);
      _machine.frames.add([kept]);
      final lost = _create(1);
      _machine.store64(lost + 8, kept);
      _create(1);
      expect(_isAllocated(kept), isTrue);
      expect(_machine.collections, 3);
      // The same memory serves again, and held garbage in between.
      final again = _create(1);
      expect(again, isNot(kept));
      expect(_machine.load64(again + 8), 0);
    });

    test('fills freed memory with garbage when asked', () {
      _start(collectsAlways: true);
      final kept = _create(2);
      _machine.frames.add([kept]);
      final lost = _create(2);
      _machine.store64(lost + 24, 5);
      collect();
      expect(_machine.load64(lost + 24), isNot(anyOf(0, 5)));
      expect(_machine.load64(kept + 24), 0);
    });
  });

  for (final always in [false, true]) {
    test('random graphs, collecting always: $always', () {
      final random = Random(11);
      for (var round = 0; round < 6; round++) {
        _start(collectsAlways: always);
        _randomGraph(random, always ? 400 : 4000);
      }
    });
  }
}

/// Whether the cell at [address] is in use, where it is still mapped.
bool _isAllocated(int address) {
  try {
    return _machine.load32(address + 4) & 1 != 0;
  } on StateError {
    return false;
  }
}

/// Changes a graph at random, comparing it with a model of itself.
void _randomGraph(Random random, int steps) {
  final model = <int, ({int class_, Map<int, int> fields, int mark})>{};
  var marks = 0;

  List<int> roots() => [
    for (final frame in _machine.frames) ...frame,
    for (var i = 0; i < SimulatedMachine.globalCount; i++) _machine.global(i),
  ];

  Set<int> reachable() {
    final seen = <int>{}, pending = roots();
    while (pending.isNotEmpty) {
      final object = pending.removeLast();
      if (object == 0 || !seen.add(object)) continue;
      pending.addAll(model[object]!.fields.values);
    }
    return seen;
  }

  void check() {
    final alive = reachable();
    model.removeWhere((object, _) => !alive.contains(object));
    model.forEach((object, expected) {
      expect(_machine.load32(object), expected.class_);
      expect(_machine.load32(object + 4) & 3, 1);
      expected.fields.forEach((offset, target) {
        expect(_machine.load64(object + offset), target);
      });
      // Words that are not references keep numbers that look like anything.
      if (expected.class_ == 3) {
        expect(_machine.load64(object + 8), expected.mark);
      }
    });
  }

  int any(List<int> from) => from[random.nextInt(from.length)];
  for (var step = 0; step < steps; step++) {
    final alive = [0, ...reachable()];
    switch (random.nextInt(8)) {
      case 0 when _machine.frames.length < 20:
        if (random.nextInt(4) == 0) {
          _machine.calledFromC.add(_machine.frames.length);
        }
        _machine.frames.add([
          for (var i = any(SimulatedMachine.frameSizes); i > 0; i--) any(alive),
        ]);
      case 1 when _machine.frames.isNotEmpty && random.nextInt(3) == 0:
        _machine.frames.removeLast();
        _machine.calledFromC.remove(_machine.frames.length);
      case 2:
        _machine.setGlobal(
          random.nextInt(SimulatedMachine.globalCount),
          any(alive),
        );
      case 3 || 4:
        final object = any(alive);
        final fields = model[object]?.fields;
        if (fields == null || fields.isEmpty) break;
        final offset = any(fields.keys.toList());
        fields[offset] = any(alive);
        _machine.store64(object + offset, fields[offset]!);
      case 5 when step % 50 == 0:
        collect();
        check();
      default:
        // What the new object will refer to must be kept meanwhile.
        final class_ = random.nextInt(classes.length);
        final object = _create(class_);
        check();
        expect(model.containsKey(object), isFalse);
        marks = object ^ step;
        model[object] = (
          class_: class_,
          fields: {for (final offset in classes[class_]) offset: 0},
          mark: marks,
        );
        if (class_ == 3) _machine.store64(object + 8, marks);
        _machine.setGlobal(
          random.nextInt(SimulatedMachine.globalCount),
          object,
        );
    }
  }
  collect();
  check();
}
