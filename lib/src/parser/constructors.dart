part of 'parser.dart';

final class _ConstructorReader(
  final _Parser parser,
  final int start,
  final List<int> metadata, {
  final bool external = false,
}) extends _Reader<int> {
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
    final names = <int>[];
    int? parameters;
    if (!primaryBody) {
      if (parser.current.kind != .leftParen) {
        names.add(parser.readConstructorName());
        if (parser.current.kind == .dot) {
          parser.advance();
          names.add(parser.readConstructorName());
        }
      }
      final reader = _ParameterReader(parser, function: true);
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
      int? types;
      if (parser.current.kind == .less) {
        final reader = _TypeReader(parser);
        if (!reader.start(arguments: true)) yield _TypeTask(reader);
        types = parser.arena.asTypeArgumentListOrNull(reader.result);
        if (reader.failure case final failure?) {
          parser.error(failure.$1, failure.$2, failure.$3);
        }
      }
      int? suffix;
      if (parser.current.kind == .dot) {
        parser.advance();
        suffix = parser.readConstructorName();
      }
      final body = parser.arena.putFactoryRedirectBody(
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
        result = parser.arena.putMissingClassMember(
          source: parser.source,
          offset: start,
        );
      } else {
        result = parser.arena.putConstructorDeclaration(
          source: parser.source,
          start: start,
          end: parser.arena.rEnd(body),
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
          parser.arena.rStart(initializers.result.first),
          parser.arena.rEnd(initializers.result.last),
        ),
      );
    }
    final body = _BodyReader(parser);
    yield body;
    if (keyword == .factoryKeyword &&
        !external &&
        parser.arena.isEmptyFunctionBody(body.result)) {
      parser.error(
        'missing_function_body',
        'A factory requires a body or redirection.',
        Token(
          .semicolon,
          parser.source,
          parser.arena.rStart(body.result),
          parser.arena.rEnd(body.result),
        ),
      );
    }
    if (parser.arena.isModifiedBlockFunctionBody(body.result) ||
        parser.arena.isExpressionFunctionBody(body.result) &&
            parser.arena.rExpressionFunctionBodyIsAsync(
              (parser.arena.asExpressionFunctionBody(body.result)),
            )) {
      parser.error(
        'async_constructor',
        'Constructors cannot be asynchronous or generators.',
        Token(
          .invalid,
          parser.source,
          parser.arena.rStart(body.result),
          parser.arena.rEnd(body.result),
        ),
      );
    }
    result = primaryBody
        ? parser.arena.putPrimaryConstructorBody(
            source: parser.source,
            start: start,
            end: parser.arena.rEnd(body.result),
            metadata: metadata,
            initializers: initializers.result,
            body: body.result,
          )
        : parser.arena.putConstructorDeclaration(
            source: parser.source,
            start: start,
            end: parser.arena.rEnd(body.result),
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
    extends _Reader<List<int>> {
  @override
  Iterable<_Reader<Object?>> read() sync* {
    result = [];
    if (parser.current.kind != .colon) return;
    parser.advance();
    while (true) {
      final token = parser.current;
      if (token.kind == .keywordAssert) {
        parser.advance();
        final reader = _ArgumentsReader(parser);
        yield reader;
        final arguments = parser.arena.rArgumentListArguments(reader.result);
        if (arguments.isEmpty ||
            arguments.length > 2 ||
            arguments.any((a) => parser.arena.rArgumentName(a) != null)) {
          parser.error(
            'invalid_assert',
            'An assertion requires a condition and an optional message.',
            token,
          );
        }
        result.add(
          parser.arena.putAssertInitializer(
            source: parser.source,
            start: token.start,
            end: parser.arena.rEnd(reader.result),
            condition: arguments.isEmpty
                ? parser.arena.putMissingExpression(
                    source: parser.source,
                    offset: parser.arena.rStart(reader.result),
                  )
                : parser.arena.rArgumentValue(arguments.first),
            message: arguments.length < 2
                ? null
                : parser.arena.rArgumentValue(arguments[1]),
          ),
        );
      } else {
        final hasThis = token.kind == .keywordThis;
        final hasSuper = token.kind == .keywordSuper;
        int? name;
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
                ? parser.arena.putSuperConstructorInitializer(
                    source: parser.source,
                    start: token.start,
                    end: parser.arena.rEnd(reader.result),
                    name: name,
                    arguments: reader.result,
                  )
                : parser.arena.putRedirectingConstructorInitializer(
                    source: parser.source,
                    start: token.start,
                    end: parser.arena.rEnd(reader.result),
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
          name ??= parser.arena.putIdentifier(
            source: parser.source,
            start: parser.current.start,
            end: parser.current.start,
          );
          parser.expect(.assign);
          final reader = _ExpressionReader(parser, boundary: .initializer);
          if (!reader.start()) yield reader;
          result.add(
            parser.arena.putFieldInitializer(
              source: parser.source,
              start: token.start,
              end: parser.arena.rEnd(reader.result),
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
