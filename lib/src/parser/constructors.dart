part of 'parser.dart';

final class _ConstructorReader(
  final _Parser parser,
  final int start,
  final List<Annotation> metadata, {
  final bool external = false,
}) extends _Reader<ClassMember> {
  @override
  Iterable<_Reader<Object?>> read() sync* {
    final isConst = parser.current.kind == .keywordConst;
    if (isConst) parser.advance();
    final primaryBody = parser.current.kind == .keywordThis;
    final keyword = switch (parser.current.kind) {
      .keywordNew => ConstructorKeyword.newKeyword,
      .keywordFactory => ConstructorKeyword.factoryKeyword,
      _ => ConstructorKeyword.none,
    };
    if (keyword != .none || primaryBody) parser.advance();
    final names = <Identifier>[];
    FormalParameterList? parameters;
    if (!primaryBody) {
      if (parser.current.kind != .leftParen) {
        names.add(parser.readConstructorName());
        if (parser.current.kind == .dot) {
          parser.advance();
          names.add(parser.readConstructorName());
        }
      }
      final reader = _ParameterReader(parser);
      yield reader;
      parameters = reader.result;
    }
    if (parser.current.kind == .assign) {
      final token = parser.current;
      parser.advance();
      final target = [parser.readVariableName()];
      while (parser.current.kind == .dot) {
        parser.advance();
        target.add(parser.readConstructorName());
      }
      final types = parser.readTypeArguments();
      Identifier? suffix;
      if (parser.current.kind == .dot) {
        parser.advance();
        suffix = parser.readConstructorName();
      }
      final body = FactoryRedirectBody(
        source: parser.source,
        start: token.start,
        end: parser.expect(.semicolon),
        name: target,
        typeArguments: types,
        constructorName: suffix,
      );
      if (keyword != .factoryKeyword || primaryBody) {
        parser.error(
          'invalid_redirect',
          'Only factories use an equals redirection.',
          token,
        );
      }
      if (primaryBody) {
        result = MissingClassMember(source: parser.source, offset: start);
      } else {
        result = ConstructorDeclaration(
          source: parser.source,
          start: start,
          end: body.end,
          metadata: metadata,
          isExternal: external,
          isConst: isConst,
          keyword: keyword,
          name: names,
          parameters: parameters!,
          body: body,
        );
      }
      return;
    }
    final initializers = _InitializersReader(parser);
    yield initializers;
    if (keyword == .factoryKeyword && initializers.result.isNotEmpty) {
      parser.error(
        'factory_initializer',
        'A factory cannot have initializers.',
        Token(
          .invalid,
          parser.source,
          initializers.result.first.start,
          initializers.result.last.end,
        ),
      );
    }
    final body = _BodyReader(parser);
    yield body;
    if (keyword == .factoryKeyword &&
        !external &&
        body.result is EmptyFunctionBody) {
      parser.error(
        'missing_function_body',
        'A factory requires a body or redirection.',
        Token(.semicolon, parser.source, body.result.start, body.result.end),
      );
    }
    if (body.result is ModifiedBlockFunctionBody ||
        body.result is ExpressionFunctionBody &&
            (body.result as ExpressionFunctionBody).isAsync) {
      parser.error(
        'async_constructor',
        'Constructors cannot be asynchronous or generators.',
        Token(.invalid, parser.source, body.result.start, body.result.end),
      );
    }
    result = primaryBody
        ? PrimaryConstructorBody(
            source: parser.source,
            start: start,
            end: body.result.end,
            metadata: metadata,
            initializers: initializers.result,
            body: body.result,
          )
        : ConstructorDeclaration(
            source: parser.source,
            start: start,
            end: body.result.end,
            metadata: metadata,
            isExternal: external,
            isConst: isConst,
            keyword: keyword,
            name: names,
            parameters: parameters!,
            initializers: initializers.result,
            body: body.result,
          );
  }
}

final class _InitializersReader(final _Parser parser)
    extends _Reader<List<ConstructorInitializer>> {
  @override
  Iterable<_Reader<Object?>> read() sync* {
    result = [];
    if (parser.current.kind != .colon) return;
    parser.advance();
    while (true) {
      final token = parser.current;
      if (token.kind == .keywordAssert) {
        parser.advance();
        parser.expectInitializerArguments();
        final reader = _ArgumentsReader(parser);
        yield reader;
        final arguments = reader.result.arguments;
        if (arguments.isEmpty ||
            arguments.length > 2 ||
            arguments.any((a) => a.name != null)) {
          parser.error(
            'invalid_assert',
            'An assertion requires a condition and an optional message.',
            token,
          );
        }
        result.add(
          AssertInitializer(
            source: parser.source,
            start: token.start,
            end: reader.result.end,
            condition: arguments.isEmpty
                ? MissingExpression(
                    source: parser.source,
                    offset: reader.result.start,
                  )
                : arguments.first.value,
            message: arguments.length < 2 ? null : arguments[1].value,
          ),
        );
      } else {
        final hasThis = token.kind == .keywordThis;
        final hasSuper = token.kind == .keywordSuper;
        Identifier? name;
        if (hasThis || hasSuper) {
          parser.advance();
          if (parser.current.kind == .dot) {
            parser.advance();
            name = parser.readConstructorName();
          }
        } else {
          name = parser.readVariableName();
        }
        if ((hasThis || hasSuper) && parser.current.kind == .leftParen) {
          final reader = _ArgumentsReader(parser);
          yield reader;
          result.add(
            hasSuper
                ? SuperConstructorInitializer(
                    source: parser.source,
                    start: token.start,
                    end: reader.result.end,
                    name: name,
                    arguments: reader.result,
                  )
                : RedirectingConstructorInitializer(
                    source: parser.source,
                    start: token.start,
                    end: reader.result.end,
                    name: name,
                    arguments: reader.result,
                  ),
          );
        } else {
          if (hasSuper || name == null) {
            parser.error(
              'invalid_initializer',
              'Expected a field initializer or constructor invocation.',
              token,
            );
          }
          name ??= Identifier(
            source: parser.source,
            start: parser.current.start,
            end: parser.current.start,
          );
          parser.expect(.assign);
          final reader = _ExpressionReader(parser, boundary: .initializer);
          if (!reader.start()) yield reader;
          result.add(
            FieldInitializer(
              source: parser.source,
              start: token.start,
              end: reader.result.end,
              hasThis: hasThis,
              name: name,
              value: reader.result,
            ),
          );
        }
      }
      if (parser.current.kind != .comma) break;
      parser.advance();
    }
  }
}

extension on _Parser {
  void expectInitializerArguments() {
    if (current.kind != .leftParen) {
      error('expected_token', "Expected '('.", current);
    }
  }
}
