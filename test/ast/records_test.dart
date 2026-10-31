import 'package:dartc/ast.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  test(
    'preserves interleaved positional and named fields in written order',
    () {
      final f = SyntaxFixture('const (z: first(), second(), a: third())');
      final first = f.emptyCall('first');
      final second = f.emptyCall('second');
      final third = f.emptyCall('third');
      final fields = <RecordField>[
        NamedRecordField(
          source: f.source,
          start: f.at('z:'),
          end: first.end,
          name: f.id('z'),
          value: first,
        ),
        second,
        NamedRecordField(
          source: f.source,
          start: f.at('a:'),
          end: third.end,
          name: f.id('a'),
          value: third,
        ),
      ];
      final root = RecordExpression(
        source: f.source,
        start: 0,
        end: f.source.length,
        hasConstKeyword: true,
        fields: fields,
      );
      fields.clear();
      checkTree(root);
      expect(root.hasConstKeyword, isTrue);
      expect(root.childAt(1), same(second));
      expect(walk(root).whereType<InvocationExpression>(), [
        first,
        second,
        third,
      ]);
      expect(walk(root).whereType<NamedRecordField>().map((n) => n.name.text), [
        'z',
        'a',
      ]);
      expect(() => root.fields.clear(), throwsUnsupportedError);
    },
  );

  test('distinguishes empty and singleton records from parentheses', () {
    final empty = SyntaxFixture('()');
    final emptyRecord = RecordExpression(
      source: empty.source,
      start: 0,
      end: 2,
      fields: [],
    );
    checkTree(emptyRecord);
    expect(emptyRecord.hasConstKeyword, isFalse);
    expect(emptyRecord.childCount, 0);
    final f = SyntaxFixture('(value,), (value)');
    final first = f.reference('value');
    final record = RecordExpression(
      source: f.source,
      start: 0,
      end: f.at(')') + 1,
      fields: [first],
    );
    final second = f.reference('value', record.end);
    final parens = ParenthesizedExpression(
      source: f.source,
      start: second.start - 1,
      end: second.end + 1,
      expression: second,
    );
    checkTree(record);
    checkTree(parens);
    expect(record.text, '(value,)');
    expect(parens.text, '(value)');
    expect(record.fields.single, same(first));
  });

  test('rejects reversed fields and labels outside a field range', () {
    final f = SyntaxFixture('(a: left(), right())');
    final left = f.emptyCall('left');
    final right = f.emptyCall('right');
    expect(
      () => RecordExpression(
        source: f.source,
        start: 0,
        end: f.source.length,
        fields: [right, left],
      ),
      throwsArgumentError,
    );
    expect(
      () => NamedRecordField(
        source: f.source,
        start: left.start,
        end: left.end,
        name: f.id('a'),
        value: left,
      ),
      throwsArgumentError,
    );
  });
}
