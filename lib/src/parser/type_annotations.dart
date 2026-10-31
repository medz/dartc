part of 'parser.dart';

/// Parses one written type through the end of [input].
///
/// Names remain unresolved. Nested type arguments, function types, record types,
/// nullable markers and metadata retain their source ranges.
/// Invalid input produces diagnostics; when a type cannot be
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

sealed class _AnnotatedTypeFrame extends _TypeFrame {
  List<Annotation> metadata = const [];
}

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
  final bool beforeFunction = false,
}) {
  final List<_TypeFrame> frames = [];
  (String, String, Token)? failure;
  (_TypeName, int)? relationalFallback;
  TypeParameterList? completedParameters;
  AstNode? result;
  bool beforeParameter = false;
  (TypeAnnotation, int)? parameterFallback;
  (_AnnotatedTypeFrame, _MetadataReader)? pendingMetadata;

  SourceFile get source => parser.source;
  Token get current => parser.current;
  Token get next => parser.tokens[parser.cursor + 1];

  AstNode? read({
    bool arguments = false,
    bool parameters = false,
    bool beforeParameter = false,
  }) {
    if (!start(
      arguments: arguments,
      parameters: parameters,
      beforeParameter: beforeParameter,
    )) {
      _TypeTask(this).finish();
    }
    return result;
  }

  bool start({
    bool arguments = false,
    bool parameters = false,
    bool beforeParameter = false,
  }) {
    assert(!arguments || !parameters);
    this.beforeParameter = beforeParameter;
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
      if (completedParameters != null) return complete(completedParameters);
    }
    return resume(value);
  }

  bool complete(AstNode? node) {
    result = node;
    return true;
  }

  bool resume(TypeAnnotation? value) {
    while (failure == null) {
      if (pendingMetadata != null) return false;
      if (value == null) {
        value = readHead();
        if (failure != null) break;
        if (value == null) continue;
      }
      if (current.kind == .keywordFunction &&
          (next.kind == .leftParen || next.kind == .less)) {
        if (beforeFunction &&
            frames.isEmpty &&
            parser.functionBodyAfterName(allowEmpty: true)) {
          return complete(value);
        }
        if (beforeParameter && frames.isEmpty) {
          if (parser.functionParameterAfterName()) return complete(value);
          parameterFallback = (value, parser.cursor);
        }
        value = beginFunction(value);
        continue;
      }
      if (frames.isEmpty) {
        if (parameterFallback != null &&
            !current.kind.isIdentifier &&
            current.kind != .keywordThis &&
            current.kind != .keywordSuper) {
          break;
        }
        return complete(value);
      }
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
          if (owner == null) return complete(arguments);
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
              start: frame.metadata.isEmpty
                  ? name.start
                  : frame.metadata.first.start,
              metadata: frame.metadata,
              end: value.end,
              name: name,
              bound: value,
            ),
          );
          value = continueVariables(frame);
          if (completedParameters != null) return complete(completedParameters);
        case final _FunctionTypes frame:
          Identifier? name;
          if (current.kind.isIdentifier) {
            name = readName();
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
              metadata: frame.metadata,
              type: value,
              name: name,
            ),
          );
          value = continueParameters(frame);
        case final _RecordTypes frame:
          Identifier? name;
          if (current.kind.isIdentifier) {
            name = readName();
          }
          if (frame.namedOpening == null) {
            frame.positional.add(
              PositionalRecordTypeField(
                source: source,
                start: frame.metadata.isEmpty
                    ? value.start
                    : frame.metadata.first.start,
                metadata: frame.metadata,
                end: name?.end ?? value.end,
                type: value,
                name: name,
              ),
            );
          } else if (name != null) {
            frame.named.add(
              NamedRecordTypeField(
                source: source,
                start: frame.metadata.isEmpty
                    ? value.start
                    : frame.metadata.first.start,
                metadata: frame.metadata,
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
    // Without a following parameter name, the last outer Function starts a
    // function-form parameter, as in `int Function(int value)`.
    if (parameterFallback case (final type, final index)) {
      parser.cursor = index;
      parser.current = parser.tokens[index];
      failure = null;
      return complete(type);
    }
    if (relationalFallback case (final head, final index)) {
      parser.cursor = index;
      parser.current = parser.tokens[index];
      failure = null;
      return complete(namedType(head, null));
    }
    return complete(null);
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
      fail('expected_type', 'Expected a type.');
      return null;
    }
    var name = parser.identifier(token, inType: true);
    parser.advance();
    Identifier? prefix;
    if (current.kind == .dot && token.kind != .keywordVoid) {
      prefix = name;
      parser.advance();
      if (!current.kind.isTypeName) {
        fail('expected_type', 'Expected a qualified type name.');
        return null;
      }
      name = parser.identifier(current, inType: true);
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

  bool readMetadata(_AnnotatedTypeFrame frame) {
    if (current.kind != .at) {
      frame.metadata = const [];
      return true;
    }
    pendingMetadata = (frame, _MetadataReader(_Parser.nested(parser)));
    return false;
  }

  bool resumeMetadata() {
    final (frame, metadata) = pendingMetadata!;
    pendingMetadata = null;
    final child = metadata.parser;
    frame.metadata = metadata.result;
    parser.cursor = child.cursor;
    parser.current = child.current;
    if (child.diagnostics.isNotEmpty) {
      final diagnostic = child.diagnostics.first;
      final span = diagnostic.span!;
      failure = (
        diagnostic.code.substring('parser.'.length),
        diagnostic.message,
        Token(.invalid, source, span.start, span.end),
      );
    }
    final value = switch (frame) {
      _TypeVariables() => prepareVariable(frame, afterMetadata: true),
      _FunctionTypes() => prepareParameterModifiers(frame),
      _RecordTypes() => null,
    };
    if (completedParameters != null) return complete(completedParameters);
    return resume(value);
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

  Identifier readName() {
    if (parser.functionModifier != null &&
        (current.kind == .keywordAwait || current.kind == .keywordYield)) {
      fail(
        'async_keyword_as_identifier',
        'This word cannot name a parameter or record field in an asynchronous or generator body.',
      );
    }
    final name = parser.identifier(current, inType: true);
    parser.advance();
    return name;
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

extension on _Parser {
  // This only excludes prefixes that cannot be followed by a declaration name.
  // Records, function types and generic/nullable types still use the type reader.
  bool get canStartTypeBeforeName {
    final kind = current.kind;
    if (kind == .leftParen || kind == .keywordFunction) return true;
    var index = cursor + 1;
    if (!kind.isTypeName &&
        !(kind.isIdentifier && tokens[index].kind == .dot)) {
      return false;
    }
    if (tokens[index].kind == .dot && kind != .keywordVoid) {
      index++;
      if (!tokens[index].kind.isTypeName) return false;
      index++;
    }
    final next = tokens[index].kind;
    return next.isIdentifier || next == .less || next == .question;
  }
}
