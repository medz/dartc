part of 'parser.dart';

final class _StringReader(final _Parser parser)
    extends _Reader<StringExpression> {
  @override
  Iterable<_Reader<Object?>> read() sync* {
    final token = parser.current;
    if (token.kind != .stringLiteral && token.kind != .stringStart) {
      parser.error('expected_string', 'Expected a string literal.', token);
      result = MissingStringExpression(
        source: parser.source,
        offset: token.start,
      );
      return;
    }
    parser.beginExpression();
    parser.parseStrings();
    yield* parser.readExpressionSyntax(boundary: .header);
    result = parser.finishExpression(0, 0) as StringExpression;
    if (walk(result).any((node) => node is StringInterpolation)) {
      parser.error(
        'interpolated_uri',
        'A directive string cannot contain interpolation.',
        token,
      );
    }
  }
}

final class _DirectiveReader(
  final _Parser parser,
  final int start,
  final List<Annotation> metadata,
) extends _Reader<Directive> {
  @override
  Iterable<_Reader<Object?>> read() sync* {
    final kind = parser.current.kind;
    parser.advance();
    if (kind == .keywordLibrary) {
      final name = parser.current.kind == .semicolon
          ? null
          : parser.readDottedName();
      result = LibraryDirective(
        source: parser.source,
        start: start,
        end: parser.expect(.semicolon),
        metadata: metadata,
        name: name,
      );
      return;
    }
    if (kind == .keywordPart && parser.current.kind == .keywordOf) {
      parser.advance();
      final PartOfTarget target;
      if (parser.current.kind == .stringLiteral ||
          parser.current.kind == .stringStart) {
        final reader = _StringReader(parser);
        yield reader;
        target = reader.result;
      } else {
        target = parser.readDottedName();
      }
      result = PartOfDirective(
        source: parser.source,
        start: start,
        end: parser.expect(.semicolon),
        metadata: metadata,
        target: target,
      );
      return;
    }
    final uriReader = _StringReader(parser);
    yield uriReader;
    final uri = uriReader.result;
    if (kind == .keywordPart) {
      result = PartDirective(
        source: parser.source,
        start: start,
        end: parser.expect(.semicolon),
        metadata: metadata,
        uri: uri,
      );
      return;
    }
    final configurations = <ConditionalUri>[];
    while (parser.current.kind == .keywordIf) {
      final opening = parser.current;
      parser.advance();
      parser.expect(.leftParen);
      final name = parser.readDottedName();
      StringExpression? value;
      if (parser.current.kind == .equal) {
        parser.advance();
        final reader = _StringReader(parser);
        yield reader;
        value = reader.result;
      }
      parser.expect(.rightParen);
      final reader = _StringReader(parser);
      yield reader;
      configurations.add(
        ConditionalUri(
          source: parser.source,
          start: opening.start,
          end: reader.result.end,
          name: name,
          value: value,
          uri: reader.result,
        ),
      );
    }
    var deferred = false;
    Identifier? prefix;
    if (kind == .keywordImport) {
      if (parser.current.kind == .keywordDeferred) {
        deferred = true;
        parser.advance();
        parser.expect(.keywordAs);
        prefix = parser.readVariableName();
      } else if (parser.current.kind == .keywordAs) {
        parser.advance();
        prefix = parser.readVariableName();
      }
    }
    final combinators = <NamespaceCombinator>[];
    while (parser.current.kind == .keywordShow ||
        parser.current.kind == .keywordHide) {
      final opening = parser.current;
      parser.advance();
      final names = [parser.readVariableName()];
      while (parser.current.kind == .comma) {
        parser.advance();
        names.add(parser.readVariableName());
      }
      combinators.add(
        NamespaceCombinator(
          source: parser.source,
          start: opening.start,
          end: names.last.end,
          kind: opening.kind == .keywordShow ? .show : .hide,
          names: names,
        ),
      );
    }
    final end = parser.expect(.semicolon);
    result = kind == .keywordImport
        ? ImportDirective(
            source: parser.source,
            start: start,
            end: end,
            metadata: metadata,
            uri: uri,
            configurations: configurations,
            isDeferred: deferred,
            prefix: prefix,
            combinators: combinators,
          )
        : ExportDirective(
            source: parser.source,
            start: start,
            end: end,
            metadata: metadata,
            uri: uri,
            configurations: configurations,
            combinators: combinators,
          );
  }
}

extension on _Parser {
  DottedName readDottedName() {
    final first = readVariableName();
    final components = [first];
    while (current.kind == .dot) {
      advance();
      components.add(readVariableName());
    }
    return DottedName(
      source: source,
      start: first.start,
      end: components.last.end,
      components: components,
    );
  }
}
