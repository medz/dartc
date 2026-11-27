import 'package:dartc/heap.dart';
import 'package:test/test.dart';

import 'simulated.dart';

late SimulatedMachine _machine;

void _start({bool collectsAlways = false}) {
  _machine = SimulatedMachine(collectsAlways: collectsAlways);
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

/// An array of [length] references that a global keeps, filled by [_store].
int _root(int length) {
  final array = allocate(24 + length * 8);
  _machine
    ..store32(array, arrayClass)
    ..store64(array + 16, length)
    ..setGlobal(0, array);
  return array;
}

/// Keeps [object] as the [index]th element of [array].
void _store(int array, int index, int object) =>
    _machine.store64(array + 24 + index * 8, object);

/// The limit of allocation before the next collection.
int get _limit => _machine.load64(heap + 16);

/// Cells of 16 bytes that fit in a block, after its header.
const _cells = (262144 - 48) ~/ 16;

void main() {
  test(
    'a block gives out the cells of the dead once allocation needs them',
    () {
      _start();
      final array = _root(500);
      final objects = [for (var i = 0; i < 1000; i++) _create(0)];
      final kept = [for (var i = 0; i < 1000; i += 2) objects[i]];
      for (final (i, object) in kept.indexed) {
        _store(array, i, object);
      }
      collect();
      // The dead keep their memory until their block is swept.
      expect(_machine.load32(objects[1]), 0);
      expect(_machine.load32(objects[1] + 4) & 3, 1);
      // Sweeping gives the dead and the cells never used, all but the kept.
      final found = {for (var i = 0; i < _cells; i++) _create(0)};
      expect(
        found.containsAll(objects.toSet().difference(kept.toSet())),
        isTrue,
      );
      expect(found.intersection(kept.toSet()), isEmpty);
      for (var i = 0; i < 1000; i += 2) {
        expect(_machine.load32(objects[i] + 4) & 3, 1);
      }
    },
  );

  test('a collection before sweeping unmarks what it keeps', () {
    _start();
    final objects = [for (var i = 0; i < 100; i++) _create(1)];
    for (var i = 0; i < 99; i++) {
      _machine.store64(objects[i] + 8, objects[i + 1]);
    }
    _machine.frames.add([objects[0]]);
    collect();
    // The chain now ends halfway, and nothing was swept.
    _machine.store64(objects[49] + 8, 0);
    collect();
    final found = {for (var i = 0; i < _cells; i++) _create(1)};
    expect(found.containsAll(objects.skip(50)), isTrue);
    expect(found.intersection(objects.take(50).toSet()), isEmpty);
    expect(_machine.load64(objects[49] + 8), 0);
  });

  test('blocks where nothing was kept are given back before sweeping', () {
    _start();
    final before = _machine.mapped;
    for (var i = 0; i < 40000; i++) {
      _create(2);
    }
    expect(_machine.mapped - before, greaterThan(1 << 20));
    collect();
    collect();
    expect(_machine.mapped - before, lessThan(1 << 19));
  });

  test('what is kept is counted once, swept or not', () {
    _start();
    final array = _root(200000);
    for (var i = 0; i < 200000; i++) {
      _store(array, i, _create(2));
    }
    collect();
    final limit = _limit;
    // The array has a block, and its cell a multiple of 16.
    expect(limit, 200000 * 32 + 1600032);
    collect();
    expect(_limit, limit);
    // Allocating sweeps the full blocks; one more is kept in place of one.
    _store(array, 0, _create(2));
    collect();
    expect(_limit, limit);
  });

  test('sweeping keeps cells of every size apart', () {
    _start(collectsAlways: true);
    final array = _root(300), kept = <int>[];
    for (var i = 0; i < 300; i++) {
      kept.add(_create(i % sizes.length));
      _store(array, i, kept.last);
    }
    for (var i = 0; i < 300; i++) {
      _create(i % sizes.length);
    }
    final made = {for (var i = 0; i < 300; i++) _create(i % sizes.length)};
    expect(made.intersection(kept.toSet()), isEmpty);
    for (final (i, object) in kept.indexed) {
      expect(_machine.load32(object), i % sizes.length);
    }
  });
}
