import 'package:dartc/ast.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  test(
    'retains type arguments, key/value order, null markers, and branches',
    () {
      final f = SyntaxFixture(
        "const <String, int>{?key(): ?value(), ...?other(), "
        "if (flag) 'x': one() else ...fallback()}",
      );
      final key = f.emptyCall('key');
      final value = f.emptyCall('value');
      final other = f.emptyCall('other');
      final one = f.emptyCall('one');
      final fallback = f.emptyCall('fallback');
      final entry = MapEntryElement(
        source: f.source,
        start: key.start - 1,
        end: value.end,
        key: key,
        value: value,
        isNullAwareKey: true,
        isNullAwareValue: true,
      );
      final spread = SpreadElement(
        source: f.source,
        start: other.start - 4,
        end: other.end,
        expression: other,
        isNullAware: true,
      );
      final branch = IfElement(
        source: f.source,
        start: f.at('if ('),
        end: fallback.end,
        condition: f.reference('flag'),
        thenElement: MapEntryElement(
          source: f.source,
          start: f.at("'x'"),
          end: one.end,
          key: f.string("'x'"),
          value: one,
        ),
        elseElement: SpreadElement(
          source: f.source,
          start: fallback.start - 3,
          end: fallback.end,
          expression: fallback,
        ),
      );
      final types = TypeArgumentList(
        source: f.source,
        start: f.at('<'),
        end: f.at('>') + 1,
        arguments: [f.type('String'), f.type('int')],
      );
      final elements = <CollectionElement>[entry, spread, branch];
      final root = CollectionExpression(
        source: f.source,
        start: 0,
        end: f.source.length,
        kind: .setOrMap,
        hasConstKeyword: true,
        typeArguments: types,
        elements: elements,
      );
      elements.clear();
      checkTree(root);
      expect(root.childAt(0), same(types));
      expect(root.elements, [entry, spread, branch]);
      expect(root.hasConstKeyword, isTrue);
      expect(entry.isNullAwareKey, isTrue);
      expect(entry.isNullAwareValue, isTrue);
      expect(spread.isNullAware, isTrue);
      expect(walk(root).whereType<InvocationExpression>(), [
        key,
        value,
        other,
        one,
        fallback,
      ]);
      expect(() => root.elements.clear(), throwsUnsupportedError);
    },
  );

  test(
    'keeps else on the inner conditional and direct expression elements',
    () {
      final f = SyntaxFixture(
        '[first(), if (outer) if (inner) ?nullable() else ...items(), last()]',
      );
      final first = f.emptyCall('first');
      final nullable = f.emptyCall('nullable');
      final items = f.emptyCall('items');
      final last = f.emptyCall('last');
      final inner = IfElement(
        source: f.source,
        start: f.at('if (inner)'),
        end: items.end,
        condition: f.reference('inner'),
        thenElement: NullAwareElement(
          source: f.source,
          start: nullable.start - 1,
          end: nullable.end,
          expression: nullable,
        ),
        elseElement: SpreadElement(
          source: f.source,
          start: items.start - 3,
          end: items.end,
          expression: items,
        ),
      );
      final outer = IfElement(
        source: f.source,
        start: f.at('if (outer)'),
        end: inner.end,
        condition: f.reference('outer'),
        thenElement: inner,
      );
      final root = CollectionExpression(
        source: f.source,
        start: 0,
        end: f.source.length,
        kind: .list,
        elements: [first, outer, last],
      );
      checkTree(root);
      expect(root.childAt(0), same(first));
      expect(root.childAt(2), same(last));
      expect(outer.elseElement, isNull);
      expect(inner.elseElement, isA<SpreadElement>());
      expect(walk(root).whereType<Identifier>().map((n) => n.text), [
        'first',
        'outer',
        'inner',
        'nullable',
        'items',
        'last',
      ]);
      expect(
        walk(root).whereType<NullAwareElement>().single.text,
        '?nullable()',
      );
    },
  );

  test('does not classify brace literals by spelling before analysis', () {
    for (final text in ['{}', '{...items}']) {
      final f = SyntaxFixture(text);
      final root = CollectionExpression(
        source: f.source,
        start: 0,
        end: f.source.length,
        kind: .setOrMap,
        elements: [
          if (text != '{}')
            SpreadElement(
              source: f.source,
              start: 1,
              end: f.source.length - 1,
              expression: f.reference('items'),
            ),
        ],
      );
      checkTree(root);
      expect(root.kind, CollectionLiteralKind.setOrMap);
      expect(root.hasConstKeyword, isFalse);
    }
  });

  test('keeps each map null-aware marker independent', () {
    for (final (text, keyAware, valueAware) in [
      ('k: v', false, false),
      ('?k: v', true, false),
      ('k: ?v', false, true),
      ('?k: ?v', true, true),
    ]) {
      final f = SyntaxFixture(text);
      final entry = MapEntryElement(
        source: f.source,
        start: 0,
        end: f.source.length,
        key: f.reference('k'),
        value: f.reference('v'),
        isNullAwareKey: keyAware,
        isNullAwareValue: valueAware,
      );
      checkTree(entry);
      expect(entry.isNullAwareKey, keyAware);
      expect(entry.isNullAwareValue, valueAware);
      expect(entry.childAt(0).text, 'k');
      expect(entry.childAt(1).text, 'v');
    }
  });

  test(
    'rejects overlapping elements, stale entries, and reversed branches',
    () {
      final f = SyntaxFixture('[a, b]');
      final a = f.reference('a');
      final b = f.reference('b');
      expect(
        () => CollectionExpression(
          source: f.source,
          start: 0,
          end: f.source.length,
          kind: .list,
          elements: [a, a],
        ),
        throwsArgumentError,
      );
      expect(
        () => MapEntryElement(
          source: f.source,
          start: 0,
          end: f.source.length,
          key: a,
          value: SyntaxFixture(f.source.text).reference('b'),
        ),
        throwsArgumentError,
      );
      expect(
        () => IfElement(
          source: f.source,
          start: 0,
          end: f.source.length,
          condition: b,
          thenElement: a,
        ),
        throwsArgumentError,
      );
    },
  );
}
