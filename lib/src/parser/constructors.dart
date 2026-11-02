part of 'parser.dart';

int _readConstructor(
  _Parser parser,
  int start,
  List<int> metadata, {
  bool external = false,
}) {
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
    parameters = _ParameterReader(parser, function: true).finish();
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
      if (!reader.start(arguments: true)) _TypeTask(reader).finish();
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
      return parser.arena.putMissingClassMember(offset: start);
    } else {
      return parser.arena.putConstructorDeclaration(
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
  }
  final initializers = _readInitializers(parser);
  if (keyword == .factoryKeyword && initializers.isNotEmpty) {
    parser.error(
      'factory_initializer',
      'A factory cannot have initializers.',
      Token(
        .invalid,
        parser.source,
        parser.arena.rStart(initializers.first),
        parser.arena.rEnd(initializers.last),
      ),
    );
  }
  final bodyNode = _BodyReader(parser).finish();
  if (keyword == .factoryKeyword &&
      !external &&
      parser.arena.hasKind(bodyNode, .emptyFunctionBody)) {
    parser.error(
      'missing_function_body',
      'A factory requires a body or redirection.',
      Token(
        .semicolon,
        parser.source,
        parser.arena.rStart(bodyNode),
        parser.arena.rEnd(bodyNode),
      ),
    );
  }
  if (parser.arena.hasKind(bodyNode, .modifiedBlockFunctionBody) ||
      parser.arena.hasKind(bodyNode, .expressionFunctionBody) &&
          parser.arena.rExpressionFunctionBodyIsAsync(
            (parser.arena.asExpressionFunctionBody(bodyNode)),
          )) {
    parser.error(
      'async_constructor',
      'Constructors cannot be asynchronous or generators.',
      Token(
        .invalid,
        parser.source,
        parser.arena.rStart(bodyNode),
        parser.arena.rEnd(bodyNode),
      ),
    );
  }
  return primaryBody
      ? parser.arena.putPrimaryConstructorBody(
          start: start,
          end: parser.arena.rEnd(bodyNode),
          metadata: metadata,
          initializers: initializers,
          body: bodyNode,
        )
      : parser.arena.putConstructorDeclaration(
          start: start,
          end: parser.arena.rEnd(bodyNode),
          metadata: metadata,
          isExternal: external,
          isConst: isConst,
          keyword: keyword,
          name: names,
          parameters: parameters!,
          initializers: initializers,
          body: bodyNode,
        );
}

List<int> _readInitializers(_Parser parser) {
  if (parser.current.kind != .colon) return const [];
  final result = <int>[];
  parser.advance();
  while (true) {
    final token = parser.current;
    if (token.kind == .keywordAssert) {
      parser.advance();
      final argumentList = _ArgumentsReader(parser).finish();
      final arguments = parser.arena.rArgumentListArguments(argumentList);
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
          start: token.start,
          end: parser.arena.rEnd(argumentList),
          condition: arguments.isEmpty
              ? parser.arena.putMissingExpression(
                  offset: parser.arena.rStart(argumentList),
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
        final argumentList = _ArgumentsReader(parser).finish();
        result.add(
          hasSuper
              ? parser.arena.putSuperConstructorInitializer(
                  start: token.start,
                  end: parser.arena.rEnd(argumentList),
                  name: name,
                  arguments: argumentList,
                )
              : parser.arena.putRedirectingConstructorInitializer(
                  start: token.start,
                  end: parser.arena.rEnd(argumentList),
                  name: name,
                  arguments: argumentList,
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
          start: parser.current.start,
          end: parser.current.start,
        );
        parser.expect(.assign);
        final reader = _ExpressionReader(parser, boundary: .initializer);
        if (!reader.start()) reader.finish();
        result.add(
          parser.arena.putFieldInitializer(
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
  return result;
}
