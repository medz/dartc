part of 'parser.dart';

/// Parses declared formal parameters, including their parentheses.
///
/// Keeps positional and named groups, types, names, metadata, receiver prefixes,
/// function-form suffixes and written defaults. Defaults use [parseExpression]'s
/// synchronous grammar. Omitted types and defaults remain absent.
///
/// The enclosing declaration is not known here: whether `covariant`, `var`,
/// `final`, `this.` or `super.` is permitted by that declaration is not checked.
/// Duplicate names, field binding, types and constant defaults need analysis.
/// Recovery preserves input tokens and can return an incomplete parameter list.
ParseResult<FormalParameterList> parseFormalParameterList(ScanResult input) {
  final parser = _Parser(input);
  final node = _ParameterReader(parser).read();
  while (parser.current.kind != .eof) {
    parser.unexpected();
  }
  return ParseResult._(node, parser.diagnostics);
}

final class _ParameterList(final Token opening, {final _Formal? owner}) {
  final List<FormalParameter> parameters = [];
  FormalParameterKind kind = .requiredPositional;
  TokenKind? optionalClose;
  int groupStart = 0;
  bool groupClosed = false;
  _Formal? pending;
}

final class _Formal(
  final int start,
  final List<Annotation> metadata,
  final FormalParameterKind kind,
  final ParameterPrefix prefix,
  final VariableKeyword keyword,
  final bool isCovariant,
  final TypeAnnotation? type,
  final Identifier name,
) {
  TypeParameterList? typeParameters;
  FunctionParameterSuffix? suffix;
  int get end => suffix?.end ?? name.end;
}

final class _ParameterReader(final _Parser parser) {
  final List<_ParameterList> frames = [];

  SourceFile get source => parser.source;
  Token get current => parser.current;
  Token get next => parser.tokens[parser.cursor + 1];

  FormalParameterList read() {
    open();
    while (true) {
      final frame = frames.last;
      if (frame.pending == null) {
        if (prepare(frame)) {
          final result = close(frame);
          if (frames.isEmpty) return result;
          final owner = frame.owner!;
          final question = current.kind == .question ? current.start : null;
          if (question != null) parser.advance();
          owner.suffix = FunctionParameterSuffix(
            source: source,
            start: owner.typeParameters?.start ?? result.start,
            end: question == null ? result.end : question + 1,
            typeParameters: owner.typeParameters,
            parameters: result,
            questionOffset: question,
          );
          continue;
        }
        final formal = frame.pending = head(frame);
        if (current.kind == .less) {
          final start = current.start;
          final reader = _TypeReader(parser);
          formal.typeParameters =
              reader.read(parameters: true) as TypeParameterList?;
          if (reader.failure case final failure?) {
            parser.error(failure.$1, failure.$2, failure.$3);
          }
          formal.typeParameters ??= TypeParameterList(
            source: source,
            start: start,
            end: current.start,
            parameters: const [],
          );
        }
        if (current.kind == .leftParen || formal.typeParameters != null) {
          open(owner: formal);
          continue;
        }
      }
      finish(frame);
    }
  }

  void open({_Formal? owner}) {
    final token = current;
    parser.expect(.leftParen);
    frames.add(_ParameterList(token, owner: owner));
  }

  bool prepare(_ParameterList frame) {
    if (frame.groupClosed ||
        current.kind == .rightParen ||
        current.kind == .eof) {
      return true;
    }
    if (current.kind == .leftBracket ||
        current.kind == .leftBrace ||
        current.kind == .emptyBrackets) {
      if (frame.optionalClose != null) {
        parser.error(
          'multiple_parameter_groups',
          'Only one optional parameter group is allowed.',
          current,
        );
      }
      final token = current;
      frame.kind = token.kind == .leftBrace
          ? .optionalNamed
          : .optionalPositional;
      frame.optionalClose = token.kind == .leftBrace
          ? .rightBrace
          : .rightBracket;
      frame.groupStart = frame.parameters.length;
      parser.advance();
      if (token.kind == .emptyBrackets) {
        parser.error(
          'expected_parameter',
          'Expected a parameter in the optional group.',
          token,
        );
        frame.groupClosed = true;
        return true;
      }
    }
    if (current.kind == frame.optionalClose) {
      if (frame.parameters.length == frame.groupStart) {
        parser.error(
          'expected_parameter',
          'Expected a parameter in the optional group.',
          current,
        );
      }
      parser.advance();
      frame.groupClosed = true;
      return true;
    }
    return false;
  }

  _Formal head(_ParameterList frame) {
    final start = current.start;
    final metadata = parser.readMetadata();
    var required = false;
    var covariant = false;
    var keyword = VariableKeyword.none;
    TypeAnnotation? type;
    var modifierOrder = -1;
    while (current.kind.isFormalModifier &&
        current.kind.isWrittenModifier(next.kind)) {
      final token = current;
      if (token.kind.isIdentifier && next.kind == .leftParen) {
        final index = parser.cursor;
        parser.advance();
        final parsed = _TypeReader(parser).read() as TypeAnnotation?;
        if (parsed == null ||
            !(current.kind.isIdentifier ||
                current.kind == .keywordThis ||
                current.kind == .keywordSuper)) {
          parser.cursor = index;
          parser.current = token;
          break;
        }
        type = parsed;
      }
      final order = switch (token.kind) {
        .keywordRequired => 0,
        .keywordCovariant => 1,
        _ => 2,
      };
      if (order < modifierOrder) {
        parser.error(
          'modifier_out_of_order',
          'Parameter modifiers are out of order.',
          token,
        );
      }
      modifierOrder = order;
      switch (token.kind) {
        case .keywordRequired:
          if (required || frame.kind != .optionalNamed) {
            parser.error(
              'invalid_required_parameter',
              'Only named parameters can have one required modifier.',
              token,
            );
          }
          required = true;
        case .keywordCovariant:
          if (covariant) {
            parser.error(
              'duplicate_modifier',
              'Repeated covariant modifier.',
              token,
            );
          }
          covariant = true;
        case .keywordVar || .keywordFinal || .keywordConst:
          if (keyword != .none) {
            parser.error(
              'conflicting_modifiers',
              'Conflicting parameter modifiers.',
              token,
            );
          }
          keyword = switch (token.kind) {
            .keywordVar => .varKeyword,
            .keywordFinal => .finalKeyword,
            _ => .constKeyword,
          };
          if (keyword == .constKeyword) {
            parser.error(
              'invalid_parameter_modifier',
              'A formal parameter cannot be const.',
              token,
            );
          }
          if (frame.owner != null) {
            parser.error(
              'invalid_parameter_modifier',
              'A function-form parameter cannot declare fields.',
              token,
            );
          }
        default:
          parser.error(
            'invalid_parameter_modifier',
            'This modifier cannot be used on a parameter.',
            token,
          );
      }
      if (type != null) break;
      parser.advance();
    }
    if (type == null &&
        current.kind != .keywordThis &&
        current.kind != .keywordSuper) {
      final index = parser.cursor;
      final token = current;
      final parsed = _TypeReader(parser).read() as TypeAnnotation?;
      if (parsed != null &&
          (current.kind.isIdentifier ||
              current.kind == .keywordThis ||
              current.kind == .keywordSuper)) {
        type = parsed;
      } else {
        parser.cursor = index;
        parser.current = token;
      }
    }
    var prefix = ParameterPrefix.none;
    if (current.kind == .keywordThis || current.kind == .keywordSuper) {
      prefix = current.kind == .keywordThis ? .thisKeyword : .superKeyword;
      parser.advance();
      parser.expect(.dot);
    }
    final name = parser.readVariableName();
    return _Formal(
      start,
      metadata,
      required && frame.kind == .optionalNamed ? .requiredNamed : frame.kind,
      prefix,
      keyword,
      covariant,
      type,
      name,
    );
  }

  void finish(_ParameterList frame) {
    final formal = frame.pending!;
    ParameterDefault? defaultClause;
    if (current.kind == .assign || current.kind == .colon) {
      final separator = current;
      if (formal.kind == .requiredPositional ||
          formal.kind == .optionalPositional && separator.kind == .colon ||
          frame.owner != null) {
        parser.error(
          'invalid_parameter_default',
          'This parameter cannot have this default clause.',
          separator,
        );
      }
      parser.advance();
      final value = parser.readEmbeddedExpression();
      defaultClause = ParameterDefault(
        source: source,
        start: separator.start,
        end: value.end,
        separator: separator.kind == .assign ? .equals : .colon,
        value: value,
      );
    }
    frame.parameters.add(
      FormalParameter(
        source: source,
        start: formal.start,
        end: defaultClause?.end ?? formal.end,
        metadata: formal.metadata,
        kind: formal.kind,
        prefix: formal.prefix,
        keyword: formal.keyword,
        isCovariant: formal.isCovariant,
        type: formal.type,
        name: formal.name,
        functionSuffix: formal.suffix,
        defaultClause: defaultClause,
      ),
    );
    frame.pending = null;
    if (current.kind == .comma) {
      parser.advance();
    } else if (current.kind != .rightParen &&
        current.kind != frame.optionalClose &&
        current.kind != .eof) {
      parser.error(
        'expected_parameter_separator',
        "Expected ',' or a closing parameter delimiter.",
        current,
      );
      // Keep a following declaration available after a missing comma.
      if (!current.kind.isIdentifier &&
          !current.kind.isFormalModifier &&
          current.kind != .at) {
        parser.unexpected();
      }
    }
  }

  FormalParameterList close(_ParameterList frame) {
    if (frame.optionalClose != null && !frame.groupClosed) {
      parser.expect(frame.optionalClose!);
    }
    final end = parser.expect(.rightParen);
    frames.removeLast();
    return FormalParameterList(
      source: source,
      start: frame.opening.start,
      end: end,
      parameters: frame.parameters,
    );
  }
}

extension on TokenKind {
  bool get isFormalModifier =>
      isVariableModifier ||
      this == .keywordVar ||
      this == .keywordFinal ||
      this == .keywordConst;

  bool isWrittenModifier(TokenKind next) =>
      !isIdentifier ||
      next.isKeyword ||
      next.isIdentifier ||
      next == .leftParen;
}
