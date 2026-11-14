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
      FlowIntegerRange(16, 32),
    );
    expect(
      FlowIntegerRange(-4, 2).add(FlowIntegerRange(5, 7)),
      FlowIntegerRange(1, 9),
    );
  });
}
