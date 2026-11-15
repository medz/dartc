import 'package:dartc/src/optimizer/integer_range.dart';
import 'package:test/test.dart';

void main() {
  test('interval joins and intersections retain both signed bounds', () {
    final left = FlowIntegerRange(-3, 2), right = FlowIntegerRange(0, 7);
    expect(left.join(right), FlowIntegerRange(-3, 7));
    expect(left.intersect(right), FlowIntegerRange(0, 2));
    expect(left.intersect(FlowIntegerRange(3, 4)), isNull);
    expect(
      left.join(right, widen: true),
      FlowIntegerRange(-3, FlowIntegerRange.maximum),
    );
    expect(
      right.join(left, widen: true),
      FlowIntegerRange(FlowIntegerRange.minimum, 7),
    );
    expect(() => FlowIntegerRange(1, 0), throwsArgumentError);
  });

  test('arithmetic ranges include native wrapping integer results', () {
    const points = [
      FlowIntegerRange.minimum,
      -7,
      -1,
      0,
      1,
      6,
      FlowIntegerRange.maximum,
    ];
    for (var a = 0; a < points.length; a++) {
      for (var b = a; b < points.length; b++) {
        final left = FlowIntegerRange(points[a], points[b]);
        for (var c = 0; c < points.length; c++) {
          for (var d = c; d < points.length; d++) {
            final right = FlowIntegerRange(points[c], points[d]);
            final add = left.add(right),
                subtract = left.subtract(right),
                multiply = left.multiply(right);
            for (final x in points.sublist(a, b + 1)) {
              for (final y in points.sublist(c, d + 1)) {
                expect(add.contains(x + y), isTrue);
                expect(subtract.contains(x - y), isTrue);
                expect(multiply.contains(x * y), isTrue);
              }
            }
          }
        }
      }
    }
    expect(
      FlowIntegerRange(2, 4).multiply(FlowIntegerRange(8, 8)),
      FlowIntegerRange(16, 32, zeroBits: 3),
    );
    expect(
      FlowIntegerRange(-4, 2).add(FlowIntegerRange(5, 7)),
      FlowIntegerRange(1, 9),
    );
  });

  test('alignment intersects signed bounds without inventing values', () {
    expect(
      FlowIntegerRange(-15, 15, zeroBits: 3),
      FlowIntegerRange(-8, 8, zeroBits: 3),
    );
    expect(FlowIntegerRange(0, 0).zeroBits, 64);
    expect(FlowIntegerRange(-8, -8).zeroBits, 3);
    expect(FlowIntegerRange(8, 8).zeroBits, 3);
    final aligned = FlowIntegerRange(-8, 8, zeroBits: 3);
    expect(aligned.intersect(FlowIntegerRange(1, 7)), isNull);
    expect(aligned.intersect(FlowIntegerRange(1, 9)), FlowIntegerRange(8, 8));
    expect(
      aligned.join(FlowIntegerRange(-4, 12, zeroBits: 2)),
      FlowIntegerRange(-8, 12, zeroBits: 2),
    );
    final wide = aligned.join(
      FlowIntegerRange(-16, 16, zeroBits: 3),
      widen: true,
    );
    expect(
      wide,
      FlowIntegerRange(
        FlowIntegerRange.minimum,
        FlowIntegerRange.maximum,
        zeroBits: 3,
      ),
    );
    expect(wide.contains(FlowIntegerRange.maximum), isFalse);
    expect(wide.contains(FlowIntegerRange.minimum), isTrue);
    expect(wide.intersect(FlowIntegerRange.full), wide);
    expect(
      FlowIntegerRange(FlowIntegerRange.minimum, 0, zeroBits: 64),
      FlowIntegerRange(0, 0),
    );
    for (final bits in [-1, 65]) {
      expect(() => FlowIntegerRange(0, 8, zeroBits: bits), throwsRangeError);
    }
    for (final (low, high, bits) in [
      (1, 7, 3),
      (1, FlowIntegerRange.maximum, 63),
      (FlowIntegerRange.minimum, -1, 64),
      (FlowIntegerRange.maximum, FlowIntegerRange.maximum, 1),
    ]) {
      expect(
        () => FlowIntegerRange(low, high, zeroBits: bits),
        throwsArgumentError,
      );
    }
  });

  test(
    'aligned arithmetic and unions include every concrete wrapped result',
    () {
      const points = [
        FlowIntegerRange.minimum,
        -16,
        -8,
        -1,
        0,
        1,
        8,
        16,
        FlowIntegerRange.maximum - 7,
        FlowIntegerRange.maximum,
      ];
      final ranges = [
        for (final point in points) FlowIntegerRange(point, point),
        FlowIntegerRange(-17, 17, zeroBits: 3),
        FlowIntegerRange(-17, 17, zeroBits: 3, excludesZero: true),
        FlowIntegerRange(-1, 1, excludesZero: true),
        FlowIntegerRange(0, 16, zeroBits: 3, excludesZero: true),
        FlowIntegerRange(-16, 0, zeroBits: 3, excludesZero: true),
        for (final bits in [0, 1, 3, 63, 64])
          FlowIntegerRange(
            FlowIntegerRange.minimum,
            FlowIntegerRange.maximum,
            zeroBits: bits,
          ),
      ];
      for (final left in ranges) {
        for (final right in ranges) {
          final union = left.join(right), intersection = left.intersect(right);
          final add = left.add(right),
              subtract = left.subtract(right),
              multiply = left.multiply(right);
          for (final x in points) {
            expect(
              intersection?.contains(x) ?? false,
              left.contains(x) && right.contains(x),
            );
            if (left.contains(x) || right.contains(x)) {
              expect(union.contains(x), isTrue);
            }
            if (!left.contains(x)) continue;
            for (final y in points.where(right.contains)) {
              expect(add.contains(x + y), isTrue);
              expect(subtract.contains(x - y), isTrue);
              expect(multiply.contains(x * y), isTrue);
            }
          }
        }
      }
    },
  );
}
