@Tags(['assets', 'native'])
library;

import 'dart:ffi';

import 'package:test/test.dart';

import 'fixtures/native_aggregates.dart';
import 'fixtures/native_aggregates_ffi.dart';

void main() {
  late NativeAggregates native;
  setUpAll(() {
    native = NativeAggregates();
    addTearDown(native.close);
  });
  test('homogeneous, mixed and large values cross the SDK FFI boundary', () {
    final point = Struct.create<Point>()
      ..x = 1.25
      ..y = -7;
    final moved = native.translate(point, 3.5);
    expect((moved.x, moved.y), (4.75, -10.5));
    expect((point.x, point.y), (1.25, -7));
    final mixed = Struct.create<Mixed>()
      ..tag = 42
      ..value = 1.125;
    final changed = native.mixed(mixed, -123);
    expect((changed.tag, changed.value), (-123, 2.25));
    expect((mixed.tag, mixed.value), (42, 1.125));
    final large = Struct.create<Large>()
      ..first = 7
      ..second = -9
      ..third = 0x123456789;
    final result = native.large(large, 5);
    expect((result.first, result.second, result.third), (0x12345678e, 7, -9));
    final choice = Union.create<Choice>()..value = 1.25;
    expect(native.union(choice).value, -1.25);
  });
  test('typed native states remain independent across calls', () {
    final first = native.createState(), second = native.createState();
    addTearDown(() {
      native.freeState(first);
      native.freeState(second);
    });
    for (var i = 0; i < 50; i++) {
      native.accumulate(first, 0.5);
    }
    native.accumulate(second, -3.25);
    expect((first.ref.tag, first.ref.value), (50, 25.0));
    expect((second.ref.tag, second.ref.value), (1, -3.25));
  });
  test('packed fields, nested owners and booleans survive allocation', () {
    final packed = Struct.create<PackedValue>()
      ..tag = 254
      ..value = -1.25;
    final result = native.packed(packed);
    expect((result.tag, result.value), (255, -0.75));
    final nested = Struct.create<Nested>()
      ..enabled = false
      ..count = 13;
    nested.point
      ..x = 1
      ..y = 2;
    final updated = native.nested(nested, true);
    expect(
      (updated.point.x, updated.point.y, updated.enabled, updated.count),
      (1.0, 4.0, true, 13 + sizeOf<Nested>()),
    );
    expect(nested.point.y, 2);
  });
  test(
    'aggregate function pointers invoke SDK callbacks in both ABI directions',
    () {
      final point = NativeCallable<PointTransform>.isolateLocal((
        Point value,
        double delta,
      ) {
        value.x *= delta;
        value.y += delta;
        return value;
      });
      final large = NativeCallable<LargeTransform>.isolateLocal((
        Large value,
        int delta,
      ) {
        value.first += delta;
        value.second *= 2;
        return value;
      });
      addTearDown(() {
        point.close();
        large.close();
      });
      final input = Struct.create<Point>()
        ..x = 1.5
        ..y = -2;
      final result = native.applyPoint(point.nativeFunction, input, 4);
      expect((result.x, result.y), (6.0, 2.0));
      final big = Struct.create<Large>()
        ..first = 12
        ..second = 13
        ..third = 14;
      final output = native.applyLarge(large.nativeFunction, big, -7);
      expect((output.first, output.second, output.third), (5, 26, 14));
    },
  );
  test(
    'whole aggregates spill when the floating register bank is exhausted',
    () {
      final input = Struct.create<Point>()
        ..x = 0.25
        ..y = 0.5;
      final result = native.stackPoint(1, 2, 3, 4, 5, 6, 7, input, 8);
      expect((result.x, result.y), (28.25, 8.5));
    },
  );
}
