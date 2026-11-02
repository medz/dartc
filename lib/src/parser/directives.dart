part of 'parser.dart';

final class _StringReader(final _Parser parser) extends _Reader<int> {
  @override
  Iterable<_Reader<Object?>> read() sync* {
    final token = parser.current;
    if (token.kind != .stringLiteral && token.kind != .stringStart) {
      parser.error('expected_string', 'Expected a string literal.', token);
      result = parser.arena.putMissingStringExpression(offset: token.start);
      return;
    }
    parser.beginExpression();
    parser.parseStrings();
    yield* parser.readExpressionSyntax(boundary: .header);
    result = parser.arena.asStringExpression(parser.finishExpression(0, 0));
    if (parser.arena
        .walkIds(result)
        .any((node) => parser.arena.hasKind(node, .stringInterpolation))) {
      parser.error(
        'interpolated_uri',
        'A directive string cannot contain interpolation.',
        token,
      );
    }
  }
}

int _readDirective(_Parser parser, int start, List<int> metadata) {
  final kind = parser.current.kind;
  parser.advance();
  if (kind == .keywordLibrary) {
    final name = parser.current.kind == .semicolon
        ? null
        : parser.readDottedName();
    return parser.arena.putLibraryDirective(
      start: start,
      end: parser.expect(.semicolon),
      metadata: metadata,
      name: name,
    );
  }
  if (kind == .keywordPart && parser.current.kind == .keywordOf) {
    parser.advance();
    final int target;
    if (parser.current.kind == .stringLiteral ||
        parser.current.kind == .stringStart) {
      target = _StringReader(parser).finish();
    } else {
      target = parser.readDottedName();
    }
    return parser.arena.putPartOfDirective(
      start: start,
      end: parser.expect(.semicolon),
      metadata: metadata,
      target: target,
    );
  }
  final uri = _StringReader(parser).finish();
  if (kind == .keywordPart) {
    return parser.arena.putPartDirective(
      start: start,
      end: parser.expect(.semicolon),
      metadata: metadata,
      uri: uri,
    );
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
      value = _StringReader(parser).finish();
    }
    parser.expect(.rightParen);
    final uriValue = _StringReader(parser).finish();
    configurations.add(
      parser.arena.putConditionalUri(
        start: opening.start,
        end: parser.arena.rEnd(uriValue),
        name: name,
        value: value,
        uri: uriValue,
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
        start: opening.start,
        end: parser.arena.rEnd(names.last),
        kind: opening.kind == .keywordShow ? .show : .hide,
        names: names,
      ),
    );
  }
  final end = parser.expect(.semicolon);
  return kind == .keywordImport
      ? parser.arena.putImportDirective(
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
          start: start,
          end: end,
          metadata: metadata,
          uri: uri,
          configurations: configurations,
          combinators: combinators,
        );
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
      start: arena.rStart(first),
      end: arena.rEnd(components.last),
      components: components,
    );
  }
}
