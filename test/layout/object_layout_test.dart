import 'package:dartc/layout.dart';
import 'package:test/test.dart';

void main() {
  test('object slots distinguish managed references from native addresses', () {
    final fields = <ValueRepresentation>[
      .word,
      .reference,
      .floating,
      .address,
      .reference,
    ];
    final layout = ObjectLayout(fields);
    fields.clear();
    expect(layout.size, 56);
    expect(
      [for (var i = 0; i < layout.fields.length; i++) layout.offsetOf(i)],
      [16, 24, 32, 40, 48],
    );
    expect(layout.referenceOffsets, [8, 24, 48]);
    expect(() => layout.fields.clear(), throwsUnsupportedError);
    expect(() => layout.offsetOf(-1), throwsRangeError);
    expect(() => layout.offsetOf(5), throwsRangeError);
    expect(ObjectLayout([]).size, 16);
    expect(ObjectLayout([]).referenceOffsets, [8]);
  });
}
