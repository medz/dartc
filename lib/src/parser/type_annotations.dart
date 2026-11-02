part of 'parser.dart';

/// Parses one written type through the end of [input].
///
/// Names remain unresolved. Nested type arguments, function types, record types,
/// nullable markers and metadata retain their source ranges.
/// Invalid input produces diagnostics; when a type cannot be
/// completed, the result contains a [MissingTypeAnnotation].
ParseResult<TypeAnnotation> parseTypeAnnotation(
  ScanResult input, {
  LanguageVersion languageVersion = LanguageVersion.current,
}) {
  final parser = _Parser(input, languageVersion: languageVersion);
  final reader = _TypeReader(parser);
  if (!reader.start()) _TypeTask(reader).finish();
  final node = parser.arena.asTypeAnnotationOrNull(reader.result);
  if (reader.failure case final failure?) {
    parser.error(failure.$1, failure.$2, failure.$3);
  } else {
    while (parser.current.kind != .eof) {
      parser.unexpected();
    }
  }
  return parser.finishResult(
    node ??
        parser.arena.putMissingTypeAnnotation(
          source: input.source,
          offset: input.tokens.first.start,
        ),
  );
}

sealed class _TypeFrame;

sealed class _AnnotatedTypeFrame extends _TypeFrame {
  List<int> metadata = const [];
}

final class _TypeArguments(final Token opening, {final _TypeName? owner})
    extends _TypeFrame {
  final List<int> arguments = [];
}

final class _TypeName(
  final AstArena arena,
  final int name, {
  final int? prefix,
  final bool isVoid = false,
}) {
  int get start => arena.rStartOrNull(prefix) ?? arena.rStart(name);
}

final class _TypeReader(
  final _Parser parser, {
  final bool afterIsOrAs = false,
  final bool beforeFunction = false,
}) {
  final List<_TypeFrame> frames = [];
  (String, String, Token)? failure;
  (_TypeName, int)? relationalFallback;
  int? completedParameters;
  int? result;
  bool beforeParameter = false;
  (int, int)? parameterFallback;
  (_AnnotatedTypeFrame, _MetadataReader)? pendingMetadata;

  SourceFile get source => parser.source;
  Token get current => parser.current;
  Token get next => parser.tokens[parser.cursor + 1];

  bool start({
    bool arguments = false,
    bool parameters = false,
    bool beforeParameter = false,
  }) {
    assert(!arguments || !parameters);
    this.beforeParameter = beforeParameter;
    int? value;
    if (arguments) {
      frames.add(_TypeArguments(current));
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

  bool complete(int? node) {
    result = node;
    return true;
  }

  bool resume(int? value) {
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
          final arguments = parser.arena.putTypeArgumentList(
            source: source,
            start: frame.opening.start,
            end: end,
            arguments: frame.arguments,
          );
          final owner = frame.owner;
          if (owner == null) return complete(arguments);
          if (frames.isEmpty) relationalFallback = null;
          value = namedType(owner, arguments);
        case final _TypeVariables frame:
          if (frame.boundStart!.kind == .keywordVoid &&
              parser.arena.isNamedTypeAnnotation(value) &&
              parser.arena.rNamedTypeAnnotationPrefix(value) == null) {
            failure = (
              'invalid_void_type',
              'A type parameter bound cannot be void.',
              frame.boundStart!,
            );
            break;
          }
          final name = frame.name!;
          frame.parameters.add(
            parser.arena.putTypeParameter(
              source: source,
              start: frame.metadata.isEmpty
                  ? parser.arena.rStart(name)
                  : parser.arena.rStart(frame.metadata.first),
              metadata: frame.metadata,
              end: parser.arena.rEnd(value),
              name: name,
              bound: value,
            ),
          );
          value = continueVariables(frame);
          if (completedParameters != null) return complete(completedParameters);
        case final _FunctionTypes frame:
          int? name;
          if (current.kind.isIdentifier) {
            name = readName();
          }
          final named = frame.kind == .optionalNamed;
          if (named && name == null) {
            fail('expected_identifier', 'Expected a named parameter name.');
          }
          frame.parameters.add(
            parser.arena.putFunctionTypeParameter(
              source: source,
              start: frame.parameterStart,
              end: parser.arena.rEndOrNull(name) ?? parser.arena.rEnd(value),
              kind: frame.requiredKeyword ? .requiredNamed : frame.kind,
              isCovariant: frame.covariantKeyword,
              metadata: frame.metadata,
              type: value,
              name: name,
            ),
          );
          value = continueParameters(frame);
        case final _RecordTypes frame:
          int? name;
          if (current.kind.isIdentifier) {
            name = readName();
          }
          if (frame.namedOpening == null) {
            frame.positional.add(
              parser.arena.putPositionalRecordTypeField(
                source: source,
                start: frame.metadata.isEmpty
                    ? parser.arena.rStart(value)
                    : parser.arena.rStart(frame.metadata.first),
                metadata: frame.metadata,
                end: parser.arena.rEndOrNull(name) ?? parser.arena.rEnd(value),
                type: value,
                name: name,
              ),
            );
          } else if (name != null) {
            frame.named.add(
              parser.arena.putNamedRecordTypeField(
                source: source,
                start: frame.metadata.isEmpty
                    ? parser.arena.rStart(value)
                    : parser.arena.rStart(frame.metadata.first),
                metadata: frame.metadata,
                end: parser.arena.rEnd(name),
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

  int? readHead() {
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
    int? prefix;
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
      parser.arena,
      name,
      prefix: prefix,
      isVoid: token.kind == .keywordVoid && prefix == null,
    );
    if (current.kind == .less && !head.isVoid) {
      if (afterIsOrAs && frames.isEmpty) {
        relationalFallback = (head, parser.cursor);
      }
      frames.add(_TypeArguments(current, owner: head));
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

  int namedType(_TypeName head, int? arguments) {
    final question = head.isVoid ? null : nullableOffset();
    return parser.arena.putNamedTypeAnnotation(
      source: source,
      start: head.start,
      end: question == null
          ? parser.arena.rEndOrNull(arguments) ?? parser.arena.rEnd(head.name)
          : question + 1,
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

  int readName() {
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
  // Finds only the outer boundary. Contents of type argument lists, record
  // fields and function parameters are checked by the type reader after the
  // surrounding declaration or pattern has been selected.
  int? possibleTypeEnd(int index, {bool beforeFunction = false}) {
    final first = tokens[index].kind;
    var bareFunction = first == .keywordFunction;
    if (first == .leftParen) {
      final end = lookahead.closing(index);
      if (end == null) return null;
      index = end + 1;
    } else {
      if (!first.isTypeName &&
          !(first.isIdentifier && tokens[index + 1].kind == .dot)) {
        return null;
      }
      index++;
      if (tokens[index].kind == .dot) {
        bareFunction = false;
        index++;
        if (!tokens[index].kind.isTypeName) return null;
        index++;
      }
      if (tokens[index].kind == .less) {
        final end = lookahead.afterTypeArguments(index);
        if (end == null) return null;
        index = end;
      }
      if (bareFunction && tokens[index].kind == .leftParen) {
        final end = lookahead.closing(index);
        if (end == null) return null;
        index = end + 1;
      }
    }
    if (tokens[index].kind == .question) index++;
    while (tokens[index].kind == .keywordFunction) {
      if (beforeFunction &&
          functionBodyAfterName(nameIndex: index, allowEmpty: true)) {
        return index;
      }
      final suffix = index;
      index++;
      if (tokens[index].kind == .less) {
        final end = lookahead.afterTypeArguments(index);
        if (end == null) return null;
        index = end;
      }
      if (tokens[index].kind != .leftParen) return suffix;
      final end = lookahead.closing(index);
      if (end == null) return null;
      index = end + 1;
      if (tokens[index].kind == .question) index++;
    }
    return index;
  }

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

final class _RequiredTypeReader(final _Parser parser) extends _Reader<int> {
  @override
  Iterable<_Reader<Object?>> read() sync* {
    final offset = parser.current.start;
    final reader = _TypeReader(parser);
    if (!reader.start()) yield _TypeTask(reader);
    if (reader.failure case final failure?) {
      parser.error(failure.$1, failure.$2, failure.$3);
    }
    result =
        parser.arena.asTypeAnnotationOrNull(reader.result) ??
        parser.arena.putMissingTypeAnnotation(
          source: parser.source,
          offset: offset,
        );
  }
}
