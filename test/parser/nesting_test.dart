import 'package:dartc/ast.dart';
import 'package:dartc/parser.dart';
import 'package:dartc/scanner.dart';
import 'package:dartc/source.dart';
import 'package:test/test.dart';

void main() {
  test(
    'type metadata yields through every nested expression and declaration',
    () {
      const depth = 2500;
      for (final (opening, closing) in [
        ('void Function(@A(const B<', '>()) int value)'),
        ('void Function(@A(f<', '>()) int value)'),
        ('void Function(@A(null as ', ') int value)'),
        ('void Function(@A((', ' value) => 0) int outer)'),
        ('void Function(@A(<', '>[]) int value)'),
        ('void Function(@A(const .named<', '>()) int value)'),
        ('void Function(@A(<T extends ', '>(T x) => x) int value)'),
        ('void Function(@A(() { ', ' x; }) int value)'),
        ('void Function(@A(() { @tag ', ' x; }) int value)'),
        ('void Function(@A(() { ', ' f() => null; }) int value)'),
        ('void Function(@A(() { try {} on ', ' {} }) int value)'),
        ('void Function(@A(switch (x) { _ as ', ' => 0 }) int value)'),
        ('void Function(@A(switch (x) { C<', '>() => 0 }) int value)'),
        ('void Function(@A(switch (x) { ', ' y => 0 }) int value)'),
        ('void Function(@A(switch (x) { <', '>[_] => 0 }) int value)'),
        ('void Function(@A(() { for (', ' x in xs) {} }) int value)'),
      ]) {
        final text = '${opening * depth}int${closing * depth}';
        final source = SourceFile(Uri.parse('memory:metadata'), text);
        final input = scan(source);
        final tokens = [...input.tokens];
        final result = parseTypeAnnotation(input);
        expect(result.diagnostics, isEmpty, reason: opening);
        expect(result.node.text, text);
        expect(
          walk(result.node).whereType<Annotation>(),
          hasLength(depth * (opening.contains('@tag') ? 2 : 1)),
        );
        expect(input.tokens, orderedEquals(tokens));
      }
    },
  );

  test('deep collections retain every level and the innermost value', () {
    const depth = 20000;
    final source = SourceFile(
      Uri.parse('memory:nested'),
      '${'[' * depth}42${']' * depth}',
    );
    final input = scan(source);
    final tokens = [...input.tokens];
    final result = parseExpression(input);
    expect(result.diagnostics, isEmpty);
    expect(result.node.text, source.text);
    expect(
      walk(result.node).whereType<CollectionExpression>(),
      hasLength(depth),
    );
    expect(walk(result.node).whereType<LiteralExpression>().single.text, '42');
    for (var i = 0; i < tokens.length; i++) {
      expect(identical(input.tokens[i], tokens[i]), isTrue);
    }
  });

  test('deep blocks preserve the enclosed statement and complete range', () {
    const depth = 20000;
    final source = SourceFile(
      Uri.parse('memory:nested'),
      '${'{' * depth}return;${'}' * depth}',
    );
    final result = parseStatement(scan(source));
    expect(result.diagnostics, isEmpty);
    expect(result.node.text, source.text);
    expect(walk(result.node).whereType<BlockStatement>(), hasLength(depth));
    expect(walk(result.node).whereType<ReturnStatement>(), hasLength(1));
  });

  test('nested delimiters distinguish literals from assignment patterns', () {
    for (final text in [
      '[{0: [value]}, (other,)]',
      '[{0: [value]}, (other,)] = input',
      '((value, [other])) = input',
    ]) {
      final source = SourceFile(Uri.parse('memory:nested'), text);
      final result = parseExpression(scan(source));
      expect(result.diagnostics, isEmpty, reason: text);
      expect(result.node.text, text);
      expect(result.node is PatternAssignmentExpression, text.contains('='));
    }
  });

  test('unclosed and crossed delimiters recover without changing tokens', () {
    for (final text in [
      '${'[' * 4000}value',
      '${'{' * 4000}return;',
      'f(([x}), y)',
      '[{0: (value]}, tail]',
      '([value)] = other',
    ]) {
      final source = SourceFile(Uri.parse('memory:nested'), text);
      final input = scan(source);
      final tokens = [...input.tokens];
      final result = text.startsWith('{')
          ? parseStatement(input)
          : parseExpression(input);
      expect(result.hasErrors, isTrue, reason: text.length < 100 ? text : null);
      for (final node in walk(result.node)) {
        expect(identical(node.source, source), isTrue);
        expect(node.start, inInclusiveRange(0, node.end));
        expect(node.end, lessThanOrEqualTo(source.length));
      }
      for (var i = 0; i < tokens.length; i++) {
        expect(identical(input.tokens[i], tokens[i]), isTrue);
      }
    }
  });
}
