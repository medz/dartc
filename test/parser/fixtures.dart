import 'package:dartc/ast.dart';
import 'package:dartc/parser.dart';
import 'package:dartc/scanner.dart';
import 'package:dartc/source.dart';
import 'package:test/test.dart';

ParseResult<Expression> parse(String text) =>
    parseExpression(scan(SourceFile(Uri.parse('memory:test'), text)));

Expression parsed(String text) {
  final result = parse(text);
  expect(
    result.diagnostics.map((d) => '${d.code}: ${d.span?.text}'),
    isEmpty,
    reason: text.length < 300 ? text : 'expression length: ${text.length}',
  );
  return result.node;
}

String shape(AstNode node) {
  String form(String tag) =>
      '($tag${[for (var i = 0; i < node.childCount; i++) ' ${shape(node.childAt(i))}'].join()})';
  return switch (node) {
    IdentifierExpression() ||
    Identifier() ||
    LiteralExpression() ||
    StringLiteralExpression() ||
    ThisExpression() ||
    SuperExpression() => node.text,
    BinaryExpression(:final op) => form(op.spelling),
    AssignmentExpression(:final op) => form(op.spelling),
    UnaryExpression(:final op) => form(op.spelling),
    UpdateExpression(:final op, :final isPrefix) => form(
      '${isPrefix ? 'pre' : 'post'}${op.spelling}',
    ),
    ParenthesizedExpression() => form('group'),
    ConditionalExpression() => form('?:'),
    PropertyAccessExpression(:final isNullAware) => form(
      isNullAware ? '?.' : '.',
    ),
    IndexExpression(:final isNullAware) => form(isNullAware ? '?[]' : '[]'),
    NullAssertionExpression() => form('!'),
    InvocationExpression(:final callee, :final arguments) =>
      '(call ${shape(callee)}${arguments.arguments.map((a) => ' ${shape(a)}').join()})',
    Argument(:final name, :final value) =>
      name == null ? shape(value) : '(${name.text}: ${shape(value)})',
    RecordExpression(:final hasConstKeyword) => form(
      hasConstKeyword ? 'const record' : 'record',
    ),
    InstanceCreationExpression(:final kind) => form(kind.name),
    CascadeExpression(:final isNullAware) => form(
      isNullAware ? '?cascade' : 'cascade',
    ),
    CascadePropertyExpression() => form('..'),
    CascadeIndexExpression() => form('..[]'),
    DotShorthandExpression() => form('context'),
    DotShorthandReferenceExpression() => form('dot'),
    ConstDotShorthandExpression() => form('const dot'),
    ArgumentList() => form('arguments'),
    NamedRecordField(:final name, :final value) =>
      '(${name.text}: ${shape(value)})',
    AdjacentStringsExpression() => form('strings'),
    InterpolatedStringExpression() => form('string'),
    StringText() => node.text,
    StringInterpolation(:final isBraced) => form(isBraced ? r'${}' : r'$'),
    MissingExpression() => '<missing>',
    CollectionExpression(:final kind) => form(
      kind == .list ? 'list' : 'braces',
    ),
    SpreadElement(:final isNullAware) => form(isNullAware ? '...?' : '...'),
    NullAwareElement() => form('?'),
    MapEntryElement(:final isNullAwareKey, :final isNullAwareValue) => form(
      '${isNullAwareKey ? '?' : ''}:${isNullAwareValue ? '?' : ''}',
    ),
    IfElement() => form('if'),
    ForElement() => form('for'),
    ForParts() => form('parts'),
    ForInParts() => form('in'),
    DeclaredIdentifier(:final keyword) => form(keyword.name),
    _ => throw StateError('Unhandled test node ${node.runtimeType}'),
  };
}
