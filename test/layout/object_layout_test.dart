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
    expect(layout.size, 72);
    expect(
      [for (var i = 0; i < layout.fields.length; i++) layout.offsetOf(i)],
      [32, 40, 48, 56, 64],
    );
    expect(layout.referenceOffsets, [8, 40, 64]);
    expect(() => layout.fields.clear(), throwsUnsupportedError);
    expect(() => layout.offsetOf(-1), throwsRangeError);
    expect(() => layout.offsetOf(5), throwsRangeError);
    expect(ObjectLayout([]).size, 32);
    expect(ObjectLayout.sizeOffset, 24);
    expect(ObjectLayout.identityHashOffset, 16);
    expect(ObjectLayout([]).referenceOffsets, [8]);
  });
}
