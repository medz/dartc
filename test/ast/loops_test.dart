import 'package:dartc/ast.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  test('combines await-for destructuring, metadata, and a guarded if-case', () {
    final f = SyntaxFixture(
      '[await for (@tag final (x, y) in stream()) '
      'if (x case int value when guard()) value else y]',
    );
    final record = RecordPattern(
      source: f.source,
      start: f.at('(x, y)'),
      end: f.at('(x, y)') + 6,
      fields: [f.patternName('x'), f.patternName('y')],
    );
    final metadata = [f.annotation('tag')];
    final binding = PatternForInBinding(
      source: f.source,
      start: f.at('@'),
      end: record.end,
      metadata: metadata,
      isFinal: true,
      pattern: record,
    );
    metadata.clear();
    final stream = f.emptyCall('stream');
    final parts = ForInParts(
      source: f.source,
      start: binding.start,
      end: stream.end,
      target: binding,
      iterable: stream,
    );
    final value = VariablePattern(
      source: f.source,
      start: f.at('int value'),
      end: f.at('value') + 5,
      type: f.type('int'),
      name: f.id('value'),
    );
    final guard = f.emptyCall('guard');
    final guarded = GuardedPattern(
      source: f.source,
      start: value.start,
      end: guard.end,
      pattern: value,
      guard: guard,
    );
    final thenValue = f.reference('value', guard.end);
    final otherwise = f.reference('y', thenValue.end);
    final branch = IfElement(
      source: f.source,
      start: f.at('if ('),
      end: otherwise.end,
      condition: f.reference('x', f.at('if (')),
      casePattern: guarded,
      thenElement: thenValue,
      elseElement: otherwise,
    );
    final loop = ForElement(
      source: f.source,
      start: f.at('await'),
      end: branch.end,
      isAwait: true,
      parts: parts,
      body: branch,
    );
    final root = CollectionExpression(
      source: f.source,
      start: 0,
      end: f.source.length,
      kind: .list,
      elements: [loop],
    );
    checkTree(root);
    expect(loop.isAwait, isTrue);
    expect(parts.target, same(binding));
    expect(binding.isFinal, isTrue);
    expect(binding.metadata.single.name.single.text, 'tag');
    expect(() => binding.metadata.clear(), throwsUnsupportedError);
    expect(branch.childAt(1), same(guarded));
    expect(branch.childAt(2), same(thenValue));
    expect(branch.childAt(3), same(otherwise));
    expect(walk(root).whereType<InvocationExpression>(), [stream, guard]);
    expect(walk(root).whereType<Identifier>().map((n) => n.text), [
      'tag',
      'x',
      'y',
      'stream',
      'x',
      'int',
      'value',
      'guard',
      'value',
      'y',
    ]);
  });

  test('keeps traditional-loop declarations and updaters in written order', () {
    final f = SyntaxFixture(
      '[for (@tag int i = start(), j = 0; i < end(); i++, j += step()) (i, j)]',
    );
    final firstName = f.id('i', f.at('int') + 3);
    final start = f.emptyCall('start');
    final j = f.id('j');
    final zero = f.literal('0');
    final declarations = [
      VariableDeclaration(
        source: f.source,
        start: firstName.start,
        end: start.end,
        name: firstName,
        initializer: start,
      ),
      VariableDeclaration(
        source: f.source,
        start: j.start,
        end: zero.end,
        name: j,
        initializer: zero,
      ),
    ];
    final variables = VariableDeclarationList(
      source: f.source,
      start: f.at('@'),
      end: zero.end,
      metadata: [f.annotation('tag')],
      type: f.type('int'),
      declarations: declarations,
    );
    declarations.clear();
    final end = f.emptyCall('end');
    final condition = f.binary(f.reference('i', zero.end), .less, end);
    final updatedI = f.reference('i', end.end);
    final increment = UpdateExpression(
      source: f.source,
      start: updatedI.start,
      end: updatedI.end + 2,
      operand: updatedI,
      op: .increment,
      isPrefix: false,
    );
    final step = f.emptyCall('step');
    final updatedJ = f.reference('j', increment.end);
    final add = AssignmentExpression(
      source: f.source,
      start: updatedJ.start,
      end: step.end,
      left: updatedJ,
      op: .add,
      right: step,
    );
    final updaters = <Expression>[increment, add];
    final parts = ForParts(
      source: f.source,
      start: variables.start,
      end: add.end,
      initializer: variables,
      condition: condition,
      updaters: updaters,
    );
    updaters.clear();
    final bodyStart = f.at('(i, j)');
    final body = RecordExpression(
      source: f.source,
      start: bodyStart,
      end: bodyStart + 6,
      fields: [f.reference('i', bodyStart), f.reference('j', bodyStart)],
    );
    final root = ForElement(
      source: f.source,
      start: f.at('for'),
      end: body.end,
      parts: parts,
      body: body,
    );
    checkTree(root);
    expect(parts.childAt(0), same(variables));
    expect(parts.childAt(1), same(condition));
    expect(parts.childAt(2), same(increment));
    expect(parts.childAt(3), same(add));
    expect(variables.declarations.length, 2);
    expect(() => variables.declarations.clear(), throwsUnsupportedError);
    expect(() => parts.updaters.clear(), throwsUnsupportedError);
    expect(walk(root).whereType<InvocationExpression>(), [start, end, step]);
    expect(
      walk(root).last,
      same((body.fields.last as IdentifierExpression).identifier),
    );
  });

  test(
    'preserves every omitted traditional-loop clause without synthetic nodes',
    () {
      for (final (text, hasInitializer, hasCondition) in [
        (';;', false, false),
        (';ready;', false, true),
        ('seed();;', true, false),
        ('seed();ready;', true, true),
      ]) {
        final f = SyntaxFixture('$text tick()');
        final initializer = hasInitializer ? f.emptyCall('seed') : null;
        final condition = hasCondition ? f.reference('ready') : null;
        final updater = f.emptyCall('tick');
        final parts = ForParts(
          source: f.source,
          start: 0,
          end: f.source.length,
          initializer: initializer,
          condition: condition,
          updaters: [updater],
        );
        checkTree(parts);
        expect(
          [for (var i = 0; i < parts.childCount; i++) parts.childAt(i)],
          [?initializer, ?condition, updater],
        );
      }
      final f = SyntaxFixture('[for (;;) value]');
      final empty = ForParts(
        source: f.source,
        start: f.at(';;'),
        end: f.at(';;') + 2,
      );
      final loop = ForElement(
        source: f.source,
        start: 1,
        end: f.source.length - 1,
        parts: empty,
        body: f.reference('value'),
      );
      checkTree(loop);
      expect(empty.condition, isNull);
      expect(empty.childCount, 0);
      expect(walk(loop).whereType<LiteralExpression>(), isEmpty);
    },
  );

  test('distinguishes existing targets from declared for-in identifiers', () {
    final f = SyntaxFixture('final int value in values');
    final declared = DeclaredIdentifier(
      source: f.source,
      start: 0,
      end: f.at('value') + 5,
      keyword: .finalKeyword,
      type: f.type('int'),
      name: f.id('value'),
    );
    final parts = ForInParts(
      source: f.source,
      start: 0,
      end: f.source.length,
      target: declared,
      iterable: f.reference('values'),
    );
    checkTree(parts);
    expect(declared.keyword, VariableKeyword.finalKeyword);
    expect(declared.type!.text, 'int');
    final existing = SyntaxFixture('value in values');
    final name = existing.id('value');
    final assigned = ForInParts(
      source: existing.source,
      start: 0,
      end: existing.source.length,
      target: name,
      iterable: existing.reference('values'),
    );
    checkTree(assigned);
    expect(assigned.childAt(0), same(name));
    expect(walk(assigned).whereType<DeclaredIdentifier>(), isEmpty);
  });

  test('retains pattern initialization separately from its loop condition', () {
    final f = SyntaxFixture('var (x, y) = pair(); ready; next()');
    final pattern = RecordPattern(
      source: f.source,
      start: f.at('('),
      end: f.at(')') + 1,
      fields: [f.patternName('x'), f.patternName('y')],
    );
    final pair = f.emptyCall('pair');
    final declaration = PatternVariableDeclaration(
      source: f.source,
      start: 0,
      end: pair.end,
      isFinal: false,
      pattern: pattern,
      initializer: pair,
    );
    final root = ForParts(
      source: f.source,
      start: 0,
      end: f.source.length,
      initializer: declaration,
      condition: f.reference('ready'),
      updaters: [f.emptyCall('next')],
    );
    checkTree(root);
    expect(root.initializer, same(declaration));
    expect(declaration.isFinal, isFalse);
    expect(walk(root).whereType<Identifier>().map((n) => n.text), [
      'x',
      'y',
      'pair',
      'ready',
      'next',
    ]);
  });

  test('retains late typed declarations and absent variable initializers', () {
    final f = SyntaxFixture('@tag late final int x = value(), y');
    final call = f.emptyCall('value');
    final x = f.id('x');
    final y = f.id('y');
    final root = VariableDeclarationList(
      source: f.source,
      start: 0,
      end: f.source.length,
      metadata: [f.annotation('tag')],
      keyword: .finalKeyword,
      isLate: true,
      type: f.type('int'),
      declarations: [
        VariableDeclaration(
          source: f.source,
          start: x.start,
          end: call.end,
          name: x,
          initializer: call,
        ),
        VariableDeclaration(
          source: f.source,
          start: y.start,
          end: y.end,
          name: y,
        ),
      ],
    );
    checkTree(root);
    expect(root.isLate, isTrue);
    expect(root.declarations.last.initializer, isNull);
    expect(walk(root).whereType<Identifier>().map((n) => n.text), [
      'tag',
      'int',
      'x',
      'value',
      'y',
    ]);
  });

  test('retains an unguarded if-case without an extra pattern node', () {
    final f = SyntaxFixture('if (value case _) thenValue');
    final pattern = WildcardPattern(
      source: f.source,
      start: f.at('_'),
      end: f.at('_') + 1,
    );
    final root = IfElement(
      source: f.source,
      start: 0,
      end: f.source.length,
      condition: f.reference('value'),
      casePattern: pattern,
      thenElement: f.reference('thenValue'),
    );
    checkTree(root);
    expect(root.childAt(1), same(pattern));
    expect(root.childCount, 3);
    expect(walk(root).whereType<GuardedPattern>(), isEmpty);
  });

  test(
    'rejects stale loop targets, reversed clauses, and overlapping bodies',
    () {
      final f = SyntaxFixture('a b');
      expect(
        () => ForInParts(
          source: f.source,
          start: 0,
          end: 3,
          target: SyntaxFixture('a b').id('a'),
          iterable: f.reference('b'),
        ),
        throwsArgumentError,
      );
      expect(
        () => ForParts(
          source: f.source,
          start: 0,
          end: 3,
          initializer: f.reference('b'),
          condition: f.reference('a'),
        ),
        throwsArgumentError,
      );
      expect(
        () => ForElement(
          source: f.source,
          start: 0,
          end: 3,
          parts: ForParts(
            source: f.source,
            start: 0,
            end: 3,
            initializer: f.reference('b'),
          ),
          body: f.reference('a'),
        ),
        throwsArgumentError,
      );
    },
  );
}
