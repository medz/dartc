part of 'parser.dart';

/// Parses one written type through the end of [input].
///
/// Names remain unresolved. Nested type arguments, function types, record types,
/// and nullable markers retain their source ranges. Metadata parsing is not yet
/// supported. Invalid input produces diagnostics; when a type cannot be
/// completed, the result contains a [MissingTypeAnnotation].
ParseResult<TypeAnnotation> parseTypeAnnotation(ScanResult input) {
  final parser = _Parser(input);
  final reader = _TypeReader(parser);
  final node = reader.read() as TypeAnnotation?;
  if (reader.failure case final failure?) {
    parser.error(failure.$1, failure.$2, failure.$3);
  } else {
    while (parser.current.kind != .eof) {
      parser.unexpected();
    }
  }
  return ParseResult._(
    node ??
        MissingTypeAnnotation(
          source: input.source,
          offset: input.tokens.first.start,
        ),
    parser.diagnostics,
  );
}

sealed class _TypeFrame;

final class _TypeArguments(
  final Token opening,
  final int index, {
  final _TypeName? owner,
}) extends _TypeFrame {
  final List<TypeAnnotation> arguments = [];
}

final class _TypeName(
  final Identifier name, {
  final Identifier? prefix,
  final bool isVoid = false,
}) {
  int get start => prefix?.start ?? name.start;
}

final class _TypeReader(
  final _Parser parser, {
  final bool afterIsOrAs = false,
}) {
  final List<_TypeFrame> frames = [];
  (String, String, Token)? failure;
  (_TypeName, int)? relationalFallback;
  TypeParameterList? completedParameters;

  SourceFile get source => parser.source;
  Token get current => parser.current;
  Token get next => parser.tokens[parser.cursor + 1];

  AstNode? read({bool arguments = false, bool parameters = false}) {
    assert(!arguments || !parameters);
    TypeAnnotation? value;
    if (arguments) {
      frames.add(_TypeArguments(current, parser.cursor));
      parser.advance();
    }
    if (parameters) {
      final frame = _TypeVariables(current);
      frames.add(frame);
      parser.advance();
      value = prepareVariable(frame);
      if (completedParameters != null) return completedParameters;
    }
    while (failure == null) {
      if (value == null) {
        value = readHead();
        if (failure != null) break;
        if (value == null) continue;
      }
      if (current.kind == .keywordFunction &&
          (next.kind == .leftParen || next.kind == .less)) {
        value = beginFunction(value);
        continue;
      }
      if (frames.isEmpty) return value;
      switch (frames.last) {
        case final _TypeArguments frame:
          frame.arguments.add(value);
          if (current.kind == .comma) {
            parser.advance();
            value = null;
            continue;
          }
          final end = closeAngle();
          if (failure != null) break;
          frames.removeLast();
          final arguments = TypeArgumentList(
            source: source,
            start: frame.opening.start,
            end: end,
            arguments: frame.arguments,
          );
          parser._lookahead?.typeArguments[frame.index] = (
            arguments,
            parser.cursor,
            parser.current,
          );
          final owner = frame.owner;
          if (owner == null) return arguments;
          if (frames.isEmpty) relationalFallback = null;
          value = namedType(owner, arguments);
        case final _TypeVariables frame:
          if (frame.boundStart!.kind == .keywordVoid &&
              value is NamedTypeAnnotation &&
              value.prefix == null) {
            failure = (
              'invalid_void_type',
              'A type parameter bound cannot be void.',
              frame.boundStart!,
            );
            break;
          }
          final name = frame.name!;
          frame.parameters.add(
            TypeParameter(
              source: source,
              start: name.start,
              end: value.end,
              name: name,
              bound: value,
            ),
          );
          value = continueVariables(frame);
          if (completedParameters != null) return completedParameters;
        case final _FunctionTypes frame:
          Identifier? name;
          if (current.kind.isIdentifier) {
            name = parser.identifier(current);
            parser.advance();
          }
          final named = frame.kind == .optionalNamed;
          if (named && name == null) {
            fail('expected_identifier', 'Expected a named parameter name.');
          }
          frame.parameters.add(
            FunctionTypeParameter(
              source: source,
              start: frame.parameterStart,
              end: name?.end ?? value.end,
              kind: frame.requiredKeyword ? .requiredNamed : frame.kind,
              isCovariant: frame.covariantKeyword,
              type: value,
              name: name,
            ),
          );
          value = continueParameters(frame);
        case final _RecordTypes frame:
          Identifier? name;
          if (current.kind.isIdentifier) {
            name = parser.identifier(current);
            parser.advance();
          }
          if (frame.namedOpening == null) {
            frame.positional.add(
              PositionalRecordTypeField(
                source: source,
                start: value.start,
                end: name?.end ?? value.end,
                type: value,
                name: name,
              ),
            );
          } else if (name != null) {
            frame.named.add(
              NamedRecordTypeField(
                source: source,
                start: value.start,
                end: name.end,
                type: value,
                name: name,
              ),
            );
          } else {
            fail('expected_identifier', 'Expected a named record field name.');
          }
          value = continueRecord(frame);
      }
    }
    for (final frame in frames) {
      if (frame is _TypeArguments) {
        parser._lookahead?.typeArguments[frame.index] = null;
      }
    }
    if (relationalFallback case (final head, final index)) {
      parser.cursor = index;
      parser.current = parser.tokens[index];
      failure = null;
      return namedType(head, null);
    }
    return null;
  }

  TypeAnnotation? readHead() {
    final token = current;
    if (token.kind == .leftParen) {
      final frame = _RecordTypes(token);
      frames.add(frame);
      parser.advance();
      return prepareRecord(frame);
    }
    if (token.kind == .keywordFunction &&
        (next.kind == .leftParen || next.kind == .less)) {
      return beginFunction(null);
    }
    if (!token.kind.isTypeName &&
        !(token.kind.isIdentifier && next.kind == .dot)) {
      fail(
        token.kind == .at ? 'unsupported_syntax' : 'expected_type',
        token.kind == .at
            ? 'Type metadata parsing is not yet supported.'
            : 'Expected a type.',
      );
      return null;
    }
    var name = parser.identifier(token);
    parser.advance();
    Identifier? prefix;
    if (current.kind == .dot && token.kind != .keywordVoid) {
      prefix = name;
      parser.advance();
      if (!current.kind.isTypeName) {
        fail('expected_type', 'Expected a qualified type name.');
        return null;
      }
      name = parser.identifier(current);
      parser.advance();
    }
    final head = _TypeName(
      name,
      prefix: prefix,
      isVoid: token.kind == .keywordVoid && prefix == null,
    );
    if (current.kind == .less && !head.isVoid) {
      final cache = parser._lookahead?.typeArguments;
      if (cache != null && cache.containsKey(parser.cursor)) {
        final cached = cache[parser.cursor];
        if (cached == null) {
          if (afterIsOrAs && frames.isEmpty) return namedType(head, null);
          fail('expected_type', 'Expected a complete type argument list.');
          return null;
        }
        parser.cursor = cached.$2;
        parser.current = cached.$3;
        return namedType(head, cached.$1);
      }
      if (afterIsOrAs && frames.isEmpty) {
        relationalFallback = (head, parser.cursor);
      }
      frames.add(_TypeArguments(current, parser.cursor, owner: head));
      parser.advance();
      return null;
    }
    return namedType(head, null);
  }

  TypeAnnotation namedType(_TypeName head, TypeArgumentList? arguments) {
    final question = head.isVoid ? null : nullableOffset();
    return NamedTypeAnnotation(
      source: source,
      start: head.start,
      end: question == null ? arguments?.end ?? head.name.end : question + 1,
      questionOffset: question,
      prefix: head.prefix,
      name: head.name,
      typeArguments: arguments,
    );
  }

  int? nullableOffset() {
    if (current.kind != .question) return null;
    if (afterIsOrAs &&
        frames.isEmpty &&
        !next.kind.endsNullableTestType &&
        !(next.kind == .keywordFunction &&
            (parser.tokens[parser.cursor + 2].kind == .leftParen ||
                parser.tokens[parser.cursor + 2].kind == .less))) {
      return null;
    }
    final offset = current.start;
    parser.advance();
    return offset;
  }

  int closeAngle() {
    final token = current;
    final TokenKind? remainder = switch (token.kind) {
      .greater => null,
      .greaterEqual => .assign,
      .shiftRight => .greater,
      .shiftRightAssign => .greaterEqual,
      .unsignedShiftRight => .shiftRight,
      .unsignedShiftRightAssign => .shiftRightAssign,
      _ => null,
    };
    if (token.kind == .greater) {
      parser.advance();
    } else if (remainder != null) {
      parser.current = Token(remainder, source, token.start + 1, token.end);
    } else {
      fail(
        'expected_closer',
        "Expected '>' after type arguments or parameters.",
      );
      return token.start;
    }
    return token.start + 1;
  }

  void fail(String code, String message) {
    failure ??= (code, message, current);
  }
}

extension on TokenKind {
  bool get isTypeName =>
      isTypeParameterName ||
      this == .keywordDynamic ||
      this == .keywordVoid ||
      this == .keywordFunction;

  bool get isTypeParameterName => switch (this) {
    .identifier ||
    .keywordAsync ||
    .keywordAwait ||
    .keywordBase ||
    .keywordHide ||
    .keywordOf ||
    .keywordOn ||
    .keywordSealed ||
    .keywordShow ||
    .keywordSync ||
    .keywordType ||
    .keywordWhen ||
    .keywordYield => true,
    _ => false,
  };

  bool get endsNullableTestType => switch (this) {
    .rightParen ||
    .rightBracket ||
    .rightBrace ||
    .interpolationEnd ||
    .question ||
    .ifNull ||
    .comma ||
    .semicolon ||
    .colon ||
    .keywordIs ||
    .keywordAs ||
    .cascade ||
    .logicalOr ||
    .logicalAnd ||
    .eof => true,
    _ => false,
  };
}
