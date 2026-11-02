part of 'parser.dart';

final class _StringReader(final _Parser parser) extends _Reader<int> {
  @override
  Iterable<_Reader<Object?>> read() sync* {
    final token = parser.current;
    if (token.kind != .stringLiteral && token.kind != .stringStart) {
      parser.error('expected_string', 'Expected a string literal.', token);
      result = parser.arena.putMissingStringExpression(
        source: parser.source,
        offset: token.start,
      );
      return;
    }
    parser.beginExpression();
    parser.parseStrings();
    yield* parser.readExpressionSyntax(boundary: .header);
    result = parser.arena.asStringExpression(parser.finishExpression(0, 0));
    if (parser.arena
        .walkIds(result)
        .any((node) => parser.arena.isStringInterpolation(node))) {
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
  final List<int> metadata,
) extends _Reader<int> {
  @override
  Iterable<_Reader<Object?>> read() sync* {
    final kind = parser.current.kind;
    parser.advance();
    if (kind == .keywordLibrary) {
      final name = parser.current.kind == .semicolon
          ? null
          : parser.readDottedName();
      result = parser.arena.putLibraryDirective(
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
      final int target;
      if (parser.current.kind == .stringLiteral ||
          parser.current.kind == .stringStart) {
        final reader = _StringReader(parser);
        yield reader;
        target = reader.result;
      } else {
        target = parser.readDottedName();
      }
      result = parser.arena.putPartOfDirective(
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
      result = parser.arena.putPartDirective(
        source: parser.source,
        start: start,
        end: parser.expect(.semicolon),
        metadata: metadata,
        uri: uri,
      );
      return;
    }
    final configurations = <int>[];
    while (parser.current.kind == .keywordIf) {
      final opening = parser.current;
      parser.advance();
      parser.expect(.leftParen);
      final name = parser.readDottedName();
      int? value;
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
        parser.arena.putConditionalUri(
          source: parser.source,
          start: opening.start,
          end: parser.arena.rEnd(reader.result),
          name: name,
          value: value,
          uri: reader.result,
        ),
      );
    }
    var deferred = false;
    int? prefix;
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
    final combinators = <int>[];
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
        parser.arena.putNamespaceCombinator(
          source: parser.source,
          start: opening.start,
          end: parser.arena.rEnd(names.last),
          kind: opening.kind == .keywordShow ? .show : .hide,
          names: names,
        ),
      );
    }
    final end = parser.expect(.semicolon);
    result = kind == .keywordImport
        ? parser.arena.putImportDirective(
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
        : parser.arena.putExportDirective(
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
  int readDottedName() {
    final first = readVariableName();
    final components = [first];
    while (current.kind == .dot) {
      advance();
      components.add(readVariableName());
    }
    return arena.putDottedName(
      source: source,
      start: arena.rStart(first),
      end: arena.rEnd(components.last),
      components: components,
    );
  }
}
