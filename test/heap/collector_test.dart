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
  heap = 0;
}

/// A new object of a class, as compiled code creates it.
int _create(int class_) {
  final object = allocate(sizes[class_]);
  _machine.store32(object, class_);
  return object;
}

final _traps = throwsA(
  isA<StateError>().having((error) => error.message, 'message', 'Trapped.'),
);

void main() {
  setUp(_start);

  group('allocation', () {
    test('gives separate, aligned, zeroed memory', () {
      final found = <int, int>{};
      for (final bytes in [8, 16, 17, 24, 100, 512, 513, 5000, 300000]) {
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

    test('stops the program without memory', () {
      _start(available: 1 << 21);
      _machine.frames.add([0]);
      expect(() {
        for (var list = 0; ;) {
          final object = _create(1);
          _machine.store64(object + 8, list);
          list = object;
          _machine.frames.last[0] = list;
        }
      }, _traps);
      expect(() => allocate(1 << 22), _traps);
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

    test('keeps cells of every size apart', () {
      for (var bytes = 8; bytes <= 600; bytes += 8) {
        final kept = allocate(bytes);
        _machine.frames.add([kept]);
        allocate(bytes);
      }
      for (var round = 0; round < 3; round++) {
        collect();
        final given = {for (final frame in _machine.frames) frame.single};
        for (var bytes = 8; bytes <= 600; bytes += 8) {
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
      for (final bytes in [16, 496, 512]) {
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
      expect(collections(140000), 1);
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
        _machine.frames.add([
          for (var i = any(SimulatedMachine.frameSizes); i > 0; i--) any(alive),
        ]);
      case 1 when _machine.frames.isNotEmpty && random.nextInt(3) == 0:
        _machine.frames.removeLast();
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
