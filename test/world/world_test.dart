import 'dart:math';

import 'package:dartc/world.dart';
import 'package:test/test.dart';

/// Classes are numbers; each has its divisors as superclasses.
bool _isSubclass(int sub, int sup) => sub % sup == 0;

World<int, String> _world() => World(_isSubclass);

void main() {
  test('a call reaches the instantiated subclasses of its receiver', () {
    final world = _world()
      ..instantiate(4)
      ..instantiate(6)
      ..call('f', 4);
    expect(world.takeEntries(), {(4, 'f')});
    world.instantiate(8);
    expect(world.takeEntries(), {(8, 'f')});
    world.call('f', 2);
    expect(world.takeEntries(), {(6, 'f')});
  });

  test('entries are given once', () {
    final world = _world()
      ..instantiate(4)
      ..call('f', 2)
      ..call('f', 4)
      ..call('f', 2)
      ..instantiate(4);
    expect(world.takeEntries(), {(4, 'f')});
    expect(world.takeEntries(), isEmpty);
  });

  test('a class that is not instantiated is never reached', () {
    final world = _world()..call('f', 1);
    expect(world.takeEntries(), isEmpty);
    expect(world.classes, isEmpty);
  });

  test('keeps classes in the order they came', () {
    final world = _world()
      ..instantiate(6)
      ..instantiate(4);
    expect(world.classes, [6, 4]);
  });

  test('agrees with the definition in any order', () {
    final random = Random(3);
    for (var round = 0; round < 200; round++) {
      final world = _world(), found = <(int, String)>{};
      final classes = <int>{}, calls = <(String, int)>{};
      for (var i = 0; i < 12; i++) {
        final number = 1 + random.nextInt(24);
        if (random.nextBool()) {
          world.instantiate(number);
          classes.add(number);
        } else {
          final selector = 'abc'[random.nextInt(3)];
          world.call(selector, number);
          calls.add((selector, number));
        }
        if (random.nextBool()) {
          for (final entry in world.takeEntries()) {
            expect(found.add(entry), isTrue);
          }
        }
      }
      found.addAll(world.takeEntries());
      expect(found, {
        for (final c in classes)
          for (final (selector, receiver) in calls)
            if (_isSubclass(c, receiver)) (c, selector),
      });
    }
  });
}
