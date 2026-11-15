import 'package:dartc/layout.dart';
import 'package:test/test.dart';

void main() {
  test(
    'descriptors encode storage while leaving linked metadata unresolved',
    () {
      final layout = ObjectLayout(
        [.reference, .reference, .reference, .reference],
        weakFields: [0],
        ephemerons: {1: 2},
        tracesPayload: true,
      );
      expect(layout.descriptorWords, [
        72,
        2,
        8,
        64,
        72,
        null,
        1,
        1,
        40,
        48,
        56,
      ]);
      expect(ObjectLayout([]).descriptorWords, [40, 1, 8, 0, null, 0, 0]);
      expect(() => layout.descriptorWords.clear(), throwsUnsupportedError);
    },
  );

  test('weak and conditional references are excluded from strong tracing', () {
    final layout = ObjectLayout(
      [.reference, .reference, .reference, .reference],
      weakFields: [0],
      ephemerons: {1: 2},
    );
    expect(layout.referenceOffsets, [
      ObjectHeader.typeOffset,
      layout.offsetOf(3),
    ]);
    expect(() => ObjectLayout([.word], weakFields: [0]), throwsArgumentError);
    expect(
      () => ObjectLayout([.reference], weakFields: [0], ephemerons: {0: 0}),
      throwsArgumentError,
    );
  });
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
    expect(layout.size, 80);
    expect(
      [for (var i = 0; i < layout.fields.length; i++) layout.offsetOf(i)],
      [40, 48, 56, 64, 72],
    );
    expect(layout.referenceOffsets, [8, 48, 72]);
    expect(() => layout.fields.clear(), throwsUnsupportedError);
    expect(() => layout.offsetOf(-1), throwsRangeError);
    expect(() => layout.offsetOf(5), throwsRangeError);
    expect(ObjectLayout([]).size, 40);
    expect(ObjectHeader.sizeOffset, 24);
    expect(ObjectHeader.identityHashOffset, 16);
    expect(ObjectLayout([]).referenceOffsets, [8]);
    final buffer = ObjectLayout([], tracesPayload: true);
    expect(buffer.size, 40);
    expect(buffer.referenceOffsets, [8]);
    expect(buffer.tracesPayload, isTrue);
    expect(layout.tracesPayload, isFalse);
  });
}
