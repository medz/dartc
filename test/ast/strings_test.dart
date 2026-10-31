import 'package:dartc/ast.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  test('retains raw spelling, escapes, UTF-16, and multiline line endings', () {
    for (final text in [
      r"r'$raw\n'",
      r'"\u{1F600}\x41"',
      "''' \r\n😀\r\nbody'''",
      'r"""\r\n\$text\\n"""',
      "'${String.fromCharCode(0xd800)}'",
    ]) {
      final f = SyntaxFixture(text);
      final literal = f.string(text);
      checkTree(literal);
      expect(literal.text, text);
      expect(literal.length, text.length);
      expect(walk(literal), [literal]);
    }
  });

  test('keeps nested and adjacent interpolations in source order', () {
    final f = SyntaxFixture(r'"a$name${"b${value()}"}$this"');
    final call = f.emptyCall('value');
    final innerStart = f.at('"b');
    final innerEnd = f.at('"', innerStart + 1) + 1;
    final inner = InterpolatedStringExpression(
      source: f.source,
      start: innerStart,
      end: innerEnd,
      parts: [
        StringText(source: f.source, start: innerStart, end: call.start - 2),
        StringInterpolation(
          source: f.source,
          start: call.start - 2,
          end: call.end + 1,
          expression: call,
          isBraced: true,
        ),
        StringText(source: f.source, start: call.end + 1, end: innerEnd),
      ],
    );
    final first = StringInterpolation(
      source: f.source,
      start: f.at(r'$name'),
      end: f.at(r'${'),
      expression: f.reference('name'),
      isBraced: false,
    );
    final nested = StringInterpolation(
      source: f.source,
      start: first.end,
      end: inner.end + 1,
      expression: inner,
      isBraced: true,
    );
    final last = StringInterpolation(
      source: f.source,
      start: f.at(r'$this'),
      end: f.source.length - 1,
      expression: ThisExpression(
        source: f.source,
        start: f.at('this'),
        end: f.source.length - 1,
      ),
      isBraced: false,
    );
    final parts = <StringPart>[
      StringText(source: f.source, start: 0, end: first.start),
      first,
      StringText(source: f.source, start: first.end, end: first.end),
      nested,
      StringText(source: f.source, start: nested.end, end: nested.end),
      last,
      StringText(source: f.source, start: last.end, end: f.source.length),
    ];
    final root = InterpolatedStringExpression(
      source: f.source,
      start: 0,
      end: f.source.length,
      parts: parts,
    );
    parts.clear();
    checkTree(root);
    expect(root.parts.map((part) => part.text).join(), f.source.text);
    expect(inner.parts.map((part) => part.text).join(), inner.text);
    expect(root.parts.whereType<StringText>().map((part) => part.text), [
      '"a',
      '',
      '',
      '"',
    ]);
    expect(walk(root).whereType<StringInterpolation>().map((n) => n.isBraced), [
      false,
      true,
      true,
      false,
    ]);
    expect(walk(root).whereType<Identifier>().map((n) => n.text), [
      'name',
      'value',
    ]);
    expect(walk(root).where((node) => identical(node, call)).length, 1);
    expect(() => root.parts.clear(), throwsUnsupportedError);
  });

  test('retains adjacency boundaries and intervening comments', () {
    final f = SyntaxFixture(r'''r'$raw' /* gap */ "hi${name}" '\n' ''');
    final first = f.string(r"r'$raw'");
    final name = f.reference('name');
    final start = f.at('"hi');
    final end = name.end + 2;
    final middle = InterpolatedStringExpression(
      source: f.source,
      start: start,
      end: end,
      parts: [
        StringText(source: f.source, start: start, end: name.start - 2),
        StringInterpolation(
          source: f.source,
          start: name.start - 2,
          end: name.end + 1,
          expression: name,
          isBraced: true,
        ),
        StringText(source: f.source, start: name.end + 1, end: end),
      ],
    );
    final last = f.string(r"'\n'");
    final strings = <StringExpression>[first, middle, last];
    final root = AdjacentStringsExpression(
      source: f.source,
      start: first.start,
      end: last.end,
      strings: strings,
    );
    strings.clear();
    checkTree(root);
    expect(root.strings, [first, middle, last]);
    expect(root.text, contains('/* gap */'));
    expect(walk(root).whereType<StringLiteralExpression>().map((n) => n.text), [
      r"r'$raw'",
      r"'\n'",
    ]);
    expect(() => root.strings.clear(), throwsUnsupportedError);
  });

  test(
    'rejects stale interpolations and reordered or overlapping segments',
    () {
      final f = SyntaxFixture(r'"$name"');
      final stale = SyntaxFixture(f.source.text).reference('name');
      expect(
        () => StringInterpolation(
          source: f.source,
          start: 1,
          end: 6,
          expression: stale,
          isBraced: false,
        ),
        throwsArgumentError,
      );
      final text = StringText(source: f.source, start: 0, end: f.source.length);
      expect(
        () => InterpolatedStringExpression(
          source: f.source,
          start: 0,
          end: f.source.length,
          parts: [text, text],
        ),
        throwsArgumentError,
      );
      final literal = f.string(f.source.text);
      expect(
        () => AdjacentStringsExpression(
          source: f.source,
          start: 0,
          end: f.source.length,
          strings: [literal, literal],
        ),
        throwsArgumentError,
      );
    },
  );
}
