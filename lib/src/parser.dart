import 'ast.dart';
import 'host.dart';
import 'scanner.dart';

class Parser {
  List<Token> tokens;
  int position;
  int pendingClosers;
  bool pendingEquals = false;
  List<String> paths;

  Parser(this.tokens, this.position, this.pendingClosers, this.paths);
}

Never parserError(Parser parser, String message) {
  var token = parser.tokens[parser.position];
  var location = '';
  if (token.source >= 0) location = parser.paths[token.source] + ':';
  print(
    'dartc parser: ' +
        location +
        message +
        ' at offset ' +
        parser.tokens[parser.position].start.toString(),
  );
  hostExit(1);
}

String parserPeek(Parser parser) {
  if (parser.pendingClosers > 0) return '>';
  if (parser.pendingEquals) return '=';
  return parser.tokens[parser.position].text;
}

bool parserIs(Parser parser, String text) {
  if (parser.pendingClosers > 0) return text == '>';
  if (parser.pendingEquals) return text == '=';
  return tokenIs(parser.tokens[parser.position], text);
}

bool parserTake(Parser parser, String text) {
  if (!parserIs(parser, text)) return false;
  if (parser.pendingClosers > 0)
    parser.pendingClosers--;
  else if (parser.pendingEquals)
    parser.pendingEquals = false;
  else
    parser.position++;
  return true;
}

void parserExpect(Parser parser, String text) {
  if (!parserTake(parser, text)) parserError(parser, 'expected ' + text);
}

String parserName(Parser parser) {
  if (parser.pendingClosers != 0 ||
      parser.pendingEquals ||
      parser.tokens[parser.position].kind != tokenIdentifier) {
    parserError(parser, 'expected identifier');
  }
  var name = parserPeek(parser);
  parser.position++;
  return name;
}

String parserTypeDeclarationName(Parser parser) {
  if (!tokenIsTypeDeclarationIdentifier(parser.tokens[parser.position]))
    parserError(parser, 'expected type declaration identifier');
  return parserName(parser);
}

bool parserTypeClose(Parser parser) {
  if (parserTake(parser, '>')) return true;
  if (parserTake(parser, '>>')) {
    parser.pendingClosers = 1;
    return true;
  }
  if (parserTake(parser, '>>>')) {
    parser.pendingClosers = 2;
    return true;
  }
  // Split only the logical remainder; physical token indices and ranges stay intact.
  if (parserTake(parser, '>=')) {
    parser.pendingEquals = true;
    return true;
  }
  if (parserTake(parser, '>>=')) {
    parser.pendingClosers = 1;
    parser.pendingEquals = true;
    return true;
  }
  if (parserTake(parser, '>>>=')) {
    parser.pendingClosers = 2;
    parser.pendingEquals = true;
    return true;
  }
  return false;
}

bool parserLookType(Parser parser, [bool declaration = false]) {
  if (parser.pendingClosers != 0 ||
      parser.pendingEquals ||
      parser.tokens[parser.position].kind != tokenIdentifier)
    return false;
  var result = false;
  if (!parserIs(parser, 'Function') ||
      !tokenIs(parser.tokens[parser.position + 1], '(') &&
          !tokenIs(parser.tokens[parser.position + 1], '<')) {
    parser.position++;
    while (parserTake(parser, '.')) {
      if (parser.pendingClosers != 0 ||
          parser.tokens[parser.position].kind != tokenIdentifier)
        return false;
      parser.position++;
    }
    if (parserTake(parser, '<')) {
      if (!parserLookType(parser)) return false;
      while (parserTake(parser, ',')) {
        if (!parserLookType(parser)) return false;
      }
      if (!parserTypeClose(parser)) return false;
    }
    parserTake(parser, '?');
    result = true;
  }
  while (parserIs(parser, 'Function') &&
      (tokenIs(parser.tokens[parser.position + 1], '(') ||
          tokenIs(parser.tokens[parser.position + 1], '<'))) {
    var tail = parser.position;
    var closers = parser.pendingClosers;
    var equals = parser.pendingEquals;
    parser.position++;
    if (parserTake(parser, '<')) {
      while (true) {
        if (parser.tokens[parser.position].kind != tokenIdentifier)
          return false;
        parser.position++;
        if (parserTake(parser, 'extends') && !parserLookType(parser))
          return false;
        if (!parserTake(parser, ',')) break;
      }
      if (!parserTypeClose(parser)) return false;
    }
    if (!parserTake(parser, '(')) return false;
    var depth = 1;
    while (depth != 0) {
      if (parserIs(parser, '')) return false;
      if (parserTake(parser, '('))
        depth++;
      else if (parserTake(parser, ')'))
        depth--;
      else
        parser.position++;
    }
    parserTake(parser, '?');
    if (declaration && parser.tokens[parser.position].kind != tokenIdentifier) {
      parser.position = tail;
      parser.pendingClosers = closers;
      parser.pendingEquals = equals;
      return result;
    }
    result = true;
  }
  return result;
}

bool parserLookTypeArguments(Parser parser) {
  if (!parserTake(parser, '<') || !parserLookType(parser)) return false;
  while (parserTake(parser, ',')) {
    if (!parserLookType(parser)) return false;
  }
  return parserTypeClose(parser);
}

bool parserHasTypeArguments(Parser parser, bool invocation) {
  var position = parser.position;
  var closers = parser.pendingClosers;
  var equals = parser.pendingEquals;
  var valid = parserLookTypeArguments(parser);
  if (valid && invocation) {
    valid =
        parser.pendingClosers == 0 &&
        !parser.pendingEquals &&
        (parserIs(parser, '(') || parserIs(parser, '.'));
  }
  parser.position = position;
  parser.pendingClosers = closers;
  parser.pendingEquals = equals;
  return valid;
}

List<AstParameter> parserFunctionTypeParameters(
  Parser parser, [
  bool legacy = false,
]) {
  parserExpect(parser, '(');
  var parameters = <AstParameter>[];
  var kind = astRequiredPositional;
  var close = ')';
  while (!parserIs(parser, close)) {
    if (kind == astRequiredPositional &&
        (parserIs(parser, '[') || parserIs(parser, '{'))) {
      kind = astOptionalPositional;
      close = ']';
      if (parserTake(parser, '{')) {
        kind = astNamedParameter;
        close = '}';
      } else
        parserExpect(parser, '[');
      if (parserIs(parser, close))
        parserError(parser, 'optional parameter group cannot be empty');
    }
    var metadata = parserMetadata(parser);
    var token = parser.position;
    var required = false;
    if (parserIs(parser, 'required')) {
      var next = parser.tokens[parser.position + 1];
      if (!legacy ||
          !tokenIs(next, ',') &&
              !tokenIs(next, ')') &&
              !tokenIs(next, ']') &&
              !tokenIs(next, '}') &&
              !tokenIs(next, '=')) {
        parser.position++;
        required = true;
      }
    }
    if (required && kind != astNamedParameter)
      parserError(parser, 'required needs a named parameter');
    if (legacy && parserIs(parser, 'covariant'))
      parserError(parser, 'covariant function type parameters are unsupported');
    if (legacy && parserIs(parser, 'var'))
      parserError(parser, 'function type parameters cannot have var');
    if (parserIs(parser, 'final') ||
        parserIs(parser, 'const') ||
        parserIs(parser, 'this') ||
        parserIs(parser, 'super')) {
      parserError(parser, 'invalid function type parameter');
    }
    AstType type;
    var name = '';
    if (legacy) {
      var end = parserDeclarationTypeEnd(parser);
      type = end < 0
          ? AstType('dynamic', const <AstType>[], token)
          : parseAstType(parser, end);
      if (tokenIsReserved(parser.tokens[parser.position]))
        parserError(parser, 'expected parameter name');
      name = parserName(parser);
      if (parserIs(parser, '<'))
        parserError(parser, 'generic function types are unsupported');
      if (parserIs(parser, '(')) {
        var nested = AstType('Function', const <AstType>[], type.token);
        nested.function = AstFunctionType(
          type,
          parserFunctionTypeParameters(parser, true),
        );
        if (parserTake(parser, '?')) nested.name = 'Function?';
        type = nested;
      }
    } else {
      type = parseAstType(parser);
      if (parser.tokens[parser.position].kind == tokenIdentifier)
        name = parserName(parser);
      if (kind == astNamedParameter && name == '')
        parserError(parser, 'named function type parameter requires a name');
    }
    if (parserIs(parser, '=') || legacy && parserIs(parser, ':'))
      parserError(
        parser,
        'function type parameters cannot have default values',
      );
    var parameter = AstParameter(type, name, false, token);
    parameter.metadata = metadata;
    parameter.kind = kind;
    parameter.required = required;
    parameters.add(parameter);
    if (!parserTake(parser, ',')) break;
  }
  if (kind != astRequiredPositional) parserExpect(parser, close);
  parserExpect(parser, ')');
  return parameters;
}

AstType parseAstType(Parser parser, [int end = -1]) {
  var token = parser.position;
  AstType result;
  if (parserIs(parser, 'Function') &&
      (tokenIs(parser.tokens[parser.position + 1], '(') ||
          tokenIs(parser.tokens[parser.position + 1], '<'))) {
    result = AstType('dynamic', const <AstType>[], token);
  } else {
    var name = parserName(parser);
    while (parserTake(parser, '.')) name = name + '.' + parserName(parser);
    List<AstType> arguments = <AstType>[];
    if (parserIs(parser, '<') && parserHasTypeArguments(parser, false)) {
      parserExpect(parser, '<');
      arguments.add(parseAstType(parser));
      while (parserTake(parser, ',')) arguments.add(parseAstType(parser));
      if (!parserTypeClose(parser)) parserError(parser, 'expected >');
    }
    if (parserTake(parser, '?')) name = name + '?';
    result = AstType(name, arguments, token);
  }
  while (parser.position != end &&
      parserIs(parser, 'Function') &&
      (tokenIs(parser.tokens[parser.position + 1], '(') ||
          tokenIs(parser.tokens[parser.position + 1], '<'))) {
    parser.position++;
    if (parserIs(parser, '<'))
      parserError(parser, 'generic function types are unsupported');
    var parameters = parserFunctionTypeParameters(parser);
    var type = AstType('Function', const <AstType>[], token);
    type.function = AstFunctionType(result, parameters);
    if (parserTake(parser, '?')) type.name = 'Function?';
    result = type;
  }
  return result;
}

List<AstType> parserTypeArguments(Parser parser) {
  parserExpect(parser, '<');
  List<AstType> arguments = <AstType>[parseAstType(parser)];
  while (parserTake(parser, ',')) arguments.add(parseAstType(parser));
  if (!parserTypeClose(parser)) parserError(parser, 'expected >');
  return arguments;
}

AstExpression parserList(Parser parser, List<AstType> arguments, int token) {
  parserExpect(parser, '[');
  List<AstExpression> children = <AstExpression>[];
  while (!parserIs(parser, ']')) {
    children.add(parserCollectionElement(parser));
    if (!parserTake(parser, ',')) break;
  }
  parserExpect(parser, ']');
  return AstExpression(astList, '', children, arguments, token);
}

AstExpression parserCollectionElement(Parser parser) {
  var token = parser.position;
  if (parserTake(parser, '?'))
    return AstExpression(
      astNullAwareElement,
      '',
      <AstExpression>[parseExpression(parser)],
      const <AstType>[],
      token,
    );
  if (parserTake(parser, '...') || parserTake(parser, '...?')) {
    var operator = parser.tokens[token].text;
    return AstExpression(
      astSpreadElement,
      operator,
      <AstExpression>[parseExpression(parser)],
      const <AstType>[],
      token,
    );
  }
  if (parserTake(parser, 'if')) {
    parserExpect(parser, '(');
    var condition = parseExpression(parser);
    parserExpect(parser, ')');
    var children = <AstExpression>[condition, parserCollectionElement(parser)];
    if (parserTake(parser, 'else'))
      children.add(parserCollectionElement(parser));
    return AstExpression(astIfElement, '', children, const <AstType>[], token);
  }
  if (parserTake(parser, 'for')) {
    var result = AstExpression(
      astForElement,
      '',
      const <AstExpression>[],
      const <AstType>[],
      token,
    );
    result.loop = parserFor(parser, token, true);
    return result;
  }
  return parseExpression(parser);
}

AstStatement parserForBody(Parser parser, bool collection) {
  if (!collection) return parseStatement(parser);
  var token = parser.position;
  return AstStatement(
    astExpressionStatement,
    <AstExpression>[parserCollectionElement(parser)],
    const <AstStatement>[],
    const <AstVariable>[],
    const <AstExpression>[],
    const <AstExpression>[],
    token,
  );
}

AstStatement parserFor(Parser parser, int token, bool collection) {
  parserExpect(parser, '(');
  var initialToken = parser.position;
  var initial = parserEmptyStatement(initialToken);
  if (!parserTake(parser, ';')) {
    var metadata = parserMetadata(parser);
    initialToken = parser.position;
    if (metadata.isNotEmpty && !parserVariableStatement(parser))
      parserError(parser, 'metadata must precede a for declaration');
    if (parserVariableStatement(parser)) {
      var modifier = parserModifier(parser);
      var type = parserDeclarationType(parser, modifier);
      var name = parserName(parser);
      var variable = parserVariableInitializer(
        parser,
        type,
        name,
        modifier,
        initialToken,
      );
      variable.metadata = metadata;
      if (parserTake(parser, 'in')) {
        if (modifier == 'const' || variable.initializer.isNotEmpty) {
          parserError(
            parser,
            'for-in requires a declaration without an initializer',
          );
        }
        var iterable = parseExpression(parser);
        parserExpect(parser, ')');
        return AstStatement(
          astForInStatement,
          <AstExpression>[iterable],
          <AstStatement>[parserForBody(parser, collection)],
          <AstVariable>[variable],
          <AstExpression>[],
          <AstExpression>[],
          token,
        );
      }
      var variables = parserVariableTail(parser, variable);
      parserExpect(parser, ';');
      initial = AstStatement(
        astVariableStatement,
        <AstExpression>[],
        <AstStatement>[],
        variables,
        <AstExpression>[],
        <AstExpression>[],
        initialToken,
      );
    } else {
      var value = parseExpression(parser);
      if (parserTake(parser, 'in')) {
        if (value.kind != astName)
          parserError(parser, 'for-in target requires an identifier');
        var iterable = parseExpression(parser);
        parserExpect(parser, ')');
        return AstStatement(
          astForInStatement,
          <AstExpression>[iterable, value],
          <AstStatement>[parserForBody(parser, collection)],
          const <AstVariable>[],
          const <AstExpression>[],
          const <AstExpression>[],
          token,
        );
      }
      parserExpect(parser, ';');
      initial = AstStatement(
        astExpressionStatement,
        <AstExpression>[value],
        <AstStatement>[],
        <AstVariable>[],
        <AstExpression>[],
        <AstExpression>[],
        initialToken,
      );
    }
  }
  List<AstExpression> condition = <AstExpression>[];
  if (!parserIs(parser, ';')) condition.add(parseExpression(parser));
  parserExpect(parser, ';');
  List<AstExpression> update = <AstExpression>[];
  if (!parserIs(parser, ')')) {
    update.add(parseExpression(parser));
    while (parserTake(parser, ',')) update.add(parseExpression(parser));
  }
  parserExpect(parser, ')');
  List<AstStatement> children = <AstStatement>[
    initial,
    parserForBody(parser, collection),
  ];
  return AstStatement(
    astForStatement,
    <AstExpression>[],
    children,
    <AstVariable>[],
    condition,
    update,
    token,
  );
}

bool parserFunctionAhead(Parser parser, int position) {
  if (!tokenIs(parser.tokens[position], '(')) return false;
  var depth = 1;
  position++;
  while (depth > 0 && parser.tokens[position].kind != tokenEnd) {
    if (tokenIs(parser.tokens[position], '(')) depth++;
    if (tokenIs(parser.tokens[position], ')')) depth--;
    position++;
  }
  return depth == 0 &&
      (tokenIs(parser.tokens[position], '{') ||
          tokenIs(parser.tokens[position], '=>') ||
          tokenIs(parser.tokens[position], 'async') ||
          tokenIs(parser.tokens[position], 'sync'));
}

bool parserGenericFunctionAhead(Parser parser) {
  var position = parser.position;
  var depth = 0;
  while (parser.tokens[position].kind != tokenEnd) {
    var token = parser.tokens[position];
    if (tokenIs(token, '<')) depth++;
    if (tokenIs(token, '>')) depth--;
    if (tokenIs(token, '>>')) depth -= 2;
    if (tokenIs(token, '>>>')) depth -= 3;
    position++;
    if (depth <= 0) return depth == 0 && parserFunctionAhead(parser, position);
  }
  return false;
}

AstExpression parserFunctionExpression(Parser parser) {
  var token = parser.position;
  var parameters = parserParameters(parser);
  if (parserIs(parser, 'async') || parserIs(parser, 'sync'))
    parserError(
      parser,
      'async and generator function expressions are unsupported',
    );
  AstStatement? body;
  AstExpression? arrow;
  if (parserTake(parser, '=>'))
    arrow = parseExpression(parser);
  else {
    if (!parserIs(parser, '{'))
      parserError(parser, 'expected function expression body');
    body = parseStatement(parser);
  }
  var expression = AstExpression(
    astFunctionExpression,
    '',
    const <AstExpression>[],
    const <AstType>[],
    token,
  );
  expression.function = AstFunction(
    '',
    parserInferredType(token),
    parameters,
    body,
    arrow,
    false,
    token,
    false,
  );
  return expression;
}

AstExpression parserPrimary(Parser parser) {
  var token = parser.position;
  var current = parser.tokens[token];
  if (parserTake(parser, 'new')) {
    var expression = parserMetadatum(parser);
    if (expression.kind != astCall)
      parserError(parser, 'new requires a constructor invocation');
    expression.text = astCallNew;
    expression.token = token;
    return expression;
  }
  if (current.kind == tokenInteger) {
    parser.position++;
    return AstExpression(
      astInteger,
      current.text,
      const <AstExpression>[],
      const <AstType>[],
      token,
    );
  }
  if (current.kind == tokenString || current.kind == tokenStringPart) {
    return parserString(parser);
  }
  if (parserTake(parser, 'true') || parserTake(parser, 'false')) {
    return AstExpression(
      astBoolean,
      current.text,
      const <AstExpression>[],
      const <AstType>[],
      token,
    );
  }
  if (parserTake(parser, 'null')) {
    return AstExpression(
      astNull,
      'null',
      const <AstExpression>[],
      const <AstType>[],
      token,
    );
  }
  if (parserFunctionAhead(parser, parser.position))
    return parserFunctionExpression(parser);
  if (parserIs(parser, '<') && parserGenericFunctionAhead(parser))
    parserError(parser, 'generic function expressions are unsupported');
  if (parserTake(parser, '(')) {
    var expression = parseExpression(parser);
    parserExpect(parser, ')');
    // A parenthesized null-shorting chain cannot absorb later assignments.
    if (expression.kind == astNullAware) expression.text = '()';
    return expression;
  }
  var constant = parserTake(parser, 'const');
  if (parserIs(parser, '[')) {
    var expression = parserList(parser, <AstType>[], token);
    expression.constant = constant;
    return expression;
  }
  if (parserTake(parser, '<')) {
    List<AstType> arguments = <AstType>[parseAstType(parser)];
    if (!parserTypeClose(parser)) parserError(parser, 'expected >');
    var expression = parserList(parser, arguments, token);
    expression.constant = constant;
    return expression;
  }
  if (constant) {
    var expression = parserMetadatum(parser);
    if (expression.kind != astCall)
      parserError(parser, 'const requires a constructor invocation');
    expression.constant = true;
    return expression;
  }
  var name = parserName(parser);
  return AstExpression(
    astName,
    name,
    const <AstExpression>[],
    const <AstType>[],
    token,
  );
}

AstExpression parserCall(
  Parser parser,
  AstExpression callee,
  int token,
  List<AstType> typeArguments, [
  String disposition = astCallValue,
]) {
  parserExpect(parser, '(');
  List<AstExpression> children = <AstExpression>[callee];
  while (!parserIs(parser, ')')) {
    var argumentToken = parser.position;
    if (parser.tokens[argumentToken].kind == tokenIdentifier &&
        parser.tokens[argumentToken + 1].kind == tokenSymbol &&
        parser.tokens[argumentToken + 1].text == ':') {
      var name = parserName(parser);
      parserExpect(parser, ':');
      children.add(
        AstExpression(
          astNamedArgument,
          name,
          <AstExpression>[parseExpression(parser)],
          <AstType>[],
          argumentToken,
        ),
      );
    } else {
      children.add(parseExpression(parser));
    }
    if (!parserTake(parser, ',')) break;
  }
  parserExpect(parser, ')');
  return AstExpression(astCall, disposition, children, typeArguments, token);
}

AstExpression parserMetadatum(Parser parser) {
  var token = parser.position;
  var value = AstExpression(
    astName,
    parserName(parser),
    const <AstExpression>[],
    const <AstType>[],
    token,
  );
  var names = 1;
  while (parserTake(parser, '.')) {
    if (names == 3) parserError(parser, 'constant name has too many parts');
    names++;
    var member = parser.position;
    value = AstExpression(
      astMember,
      parserName(parser),
      <AstExpression>[value],
      const <AstType>[],
      member,
    );
  }
  var arguments = const <AstType>[];
  if (parserIs(parser, '<')) {
    if (names > 2) parserError(parser, 'expected constant constructor');
    arguments = parserTypeArguments(parser);
    if (parserTake(parser, '.')) {
      value.typeArguments = arguments;
      arguments = const <AstType>[];
      var member = parser.position;
      value = AstExpression(
        astMember,
        parserName(parser),
        <AstExpression>[value],
        const <AstType>[],
        member,
      );
    }
    if (!parserIs(parser, '('))
      parserError(parser, 'expected constant constructor arguments');
  }
  if (parserIs(parser, '('))
    value = parserCall(
      parser,
      value,
      token,
      arguments,
      value.kind == astMember ? astCallSelector : astCallIdentifier,
    );
  return value;
}

List<AstExpression> parserMetadata(Parser parser) {
  if (!parserIs(parser, '@')) return const <AstExpression>[];
  var metadata = <AstExpression>[];
  while (parserTake(parser, '@')) metadata.add(parserMetadatum(parser));
  return metadata;
}

AstExpression parserPostfix(Parser parser) {
  var parenthesized = parserIs(parser, '(');
  var expression = parserPrimary(parser);
  var disposition = astCallValue;
  if (!parenthesized && expression.kind == astName)
    disposition = astCallIdentifier;
  return parserSelectors(parser, expression, disposition, true);
}

AstExpression parserSelectors(
  Parser parser,
  AstExpression expression,
  String disposition,
  bool increment,
) {
  while (true) {
    var token = parser.position;
    if (parserIs(parser, '?.') ||
        parserIs(parser, '?') &&
            tokenIs(parser.tokens[token + 1], '[') &&
            !parserIndexIsConditional(parser)) {
      var member = parserTake(parser, '?.');
      if (!member) parser.position++;
      var receiver = parserImplicitReceiver(token);
      AstExpression access;
      var call = astCallValue;
      if (member) {
        var name = parser.position;
        access = AstExpression(
          astMember,
          parserName(parser),
          <AstExpression>[receiver],
          const <AstType>[],
          name,
        );
        call = astCallSelector;
      } else {
        parserExpect(parser, '[');
        var index = parseExpression(parser);
        parserExpect(parser, ']');
        access = AstExpression(
          astIndex,
          '[]',
          <AstExpression>[receiver, index],
          const <AstType>[],
          token,
        );
      }
      return AstExpression(
        astNullAware,
        '',
        <AstExpression>[
          expression,
          parserSelectors(parser, access, call, increment),
        ],
        const <AstType>[],
        token,
      );
    } else if (parserIs(parser, '<') && parserHasTypeArguments(parser, true)) {
      var arguments = parserTypeArguments(parser);
      if (parserIs(parser, '(')) {
        expression = parserCall(
          parser,
          expression,
          token,
          arguments,
          disposition,
        );
        disposition = astCallValue;
      } else {
        if (expression.kind != astName &&
            (expression.kind != astMember ||
                expression.children[0].kind != astName)) {
          parserError(parser, 'unsupported type application');
        }
        expression.typeArguments = arguments;
      }
    } else if (parserTake(parser, '.')) {
      var member = parser.position;
      var name = parserName(parser);
      expression = AstExpression(
        astMember,
        name,
        <AstExpression>[expression],
        <AstType>[],
        member,
      );
      disposition = astCallSelector;
    } else if (parserIs(parser, '(')) {
      expression = parserCall(
        parser,
        expression,
        token,
        const <AstType>[],
        disposition,
      );
      disposition = astCallValue;
    } else if (parserTake(parser, '[')) {
      var index = parseExpression(parser);
      parserExpect(parser, ']');
      expression = AstExpression(
        astIndex,
        '[]',
        <AstExpression>[expression, index],
        <AstType>[],
        token,
      );
      disposition = astCallValue;
    } else if (parserTake(parser, '!') ||
        increment && (parserTake(parser, '++') || parserTake(parser, '--'))) {
      expression = AstExpression(
        astPostfix,
        parser.tokens[token].text,
        <AstExpression>[expression],
        <AstType>[],
        token,
      );
      disposition = astCallValue;
    } else {
      break;
    }
  }
  return expression;
}

AstExpression parserUnary(Parser parser) {
  var token = parser.position;
  var op = parserPeek(parser);
  if (parser.tokens[token].kind == tokenSymbol &&
      (op == '-' || op == '!' || op == '~' || op == '++' || op == '--')) {
    parser.position++;
    var expression = AstExpression(
      astUnary,
      op,
      <AstExpression>[parserUnary(parser)],
      <AstType>[],
      token,
    );
    if (op == '++' || op == '--') return parserContinueNullAware(expression);
    return expression;
  }
  return parserPostfix(parser);
}

int parserPrecedence(String op) {
  if (op == '||') return 1;
  if (op == '&&') return 2;
  if (op == '==' || op == '!=') return 3;
  if (op == '<' ||
      op == '<=' ||
      op == '>' ||
      op == '>=' ||
      op == 'is' ||
      op == 'as')
    return 4;
  if (op == '|') return 5;
  if (op == '^') return 6;
  if (op == '&') return 7;
  if (op == '<<' || op == '>>' || op == '>>>') return 8;
  if (op == '+' || op == '-') return 9;
  if (op == '*' || op == '~/' || op == '%') return 10;
  return 0;
}

bool parserNullableTypeEnd(Parser parser) {
  return parser.tokens[parser.position].kind == tokenInterpolationEnd ||
      parserIs(parser, ')') ||
      parserIs(parser, '}') ||
      parserIs(parser, ']') ||
      parserIs(parser, '?') ||
      parserIs(parser, ',') ||
      parserIs(parser, ';') ||
      parserIs(parser, ':') ||
      parserIs(parser, 'is') ||
      parserIs(parser, 'as') ||
      parserIs(parser, '||') ||
      parserIs(parser, '??') ||
      parserIs(parser, '..') ||
      parserIs(parser, '?..') ||
      parserIs(parser, '&&') ||
      parserIs(parser, '');
}

AstType parserExpressionType(Parser parser) {
  var type = parseAstType(parser);
  if (type.name.endsWith('?') && !parserNullableTypeEnd(parser)) {
    type.name = type.name.substring(0, type.name.length - 1);
    parser.position--;
  }
  if (type.name == 'void' || type.name == 'void?') {
    parser.position = type.token;
    parserError(parser, 'type test or cast requires a non-void type');
  }
  return type;
}

AstExpression parserBinary(Parser parser, int minimum) {
  var expression = parserUnary(parser);
  var maximum = 10;
  var previousComparison = -1;
  while (parser.tokens[parser.position].kind != tokenString) {
    var token = parser.position;
    var op = parserPeek(parser);
    var precedence = parserPrecedence(op);
    if (precedence < minimum || precedence > maximum) break;
    parserTake(parser, op);
    if (op == 'is' || op == 'as') {
      var kind = astTypeCast;
      if (op == 'is') {
        kind = astTypeTest;
        if (parserTake(parser, '!')) op = 'is!';
      }
      var type = parserExpressionType(parser);
      expression = AstExpression(
        kind,
        op,
        <AstExpression>[expression],
        <AstType>[type],
        token,
      );
      if (parserIs(parser, 'is') || parserIs(parser, 'as'))
        parserError(parser, 'type tests and casts cannot be chained');
    } else {
      if (precedence == 3 || precedence == 4) {
        if (previousComparison == precedence) {
          parser.position = token;
          parserError(parser, 'comparison operators cannot be chained');
        }
        previousComparison = precedence;
      }
      var right = parserBinary(parser, precedence + 1);
      expression = AstExpression(
        astBinary,
        op,
        <AstExpression>[expression, right],
        <AstType>[],
        token,
      );
    }
    maximum = precedence;
  }
  return expression;
}

bool parserAssignment(String op) {
  return op == '=' ||
      op == '??=' ||
      op == '+=' ||
      op == '-=' ||
      op == '*=' ||
      op == '~/=' ||
      op == '%=' ||
      op == '&=' ||
      op == '|=' ||
      op == '^=' ||
      op == '<<=' ||
      op == '>>=' ||
      op == '>>>=';
}

AstExpression parserIfNull(Parser parser) {
  var expression = parserBinary(parser, 1);
  while (parserIs(parser, '??')) {
    var token = parser.position;
    parser.position++;
    var right = parserBinary(parser, 1);
    expression = AstExpression(
      astBinary,
      '??',
      <AstExpression>[expression, right],
      <AstType>[],
      token,
    );
  }
  return expression;
}

AstExpression parserImplicitReceiver(int token) {
  return AstExpression(
    astImplicitReceiver,
    '',
    const <AstExpression>[],
    const <AstType>[],
    token,
  );
}

// Assignment and increment belong inside the receiver's short-circuit branch.
AstExpression parserContinueNullAware(AstExpression operation) {
  var receiver = operation.children[0];
  if (receiver.kind != astNullAware || receiver.text == '()') return operation;
  operation.children[0] = receiver.children[1];
  receiver.children[1] = parserContinueNullAware(operation);
  return receiver;
}

// Prefer a conditional when the list expression has a matching top-level colon.
bool parserIndexIsConditional(Parser parser) {
  var position = parser.position + 1;
  var depth = 0;
  var questions = 0;
  while (position < parser.tokens.length) {
    var token = parser.tokens[position];
    if (tokenIs(token, '(') ||
        tokenIs(token, '[') ||
        tokenIs(token, '{') ||
        token.kind == tokenInterpolationStart) {
      depth++;
    } else if (tokenIs(token, ')') ||
        tokenIs(token, ']') ||
        tokenIs(token, '}') ||
        token.kind == tokenInterpolationEnd) {
      if (depth == 0) return false;
      depth--;
    } else if (depth == 0) {
      if (token.kind == tokenEnd ||
          tokenIs(token, ';') ||
          tokenIs(token, ',') ||
          tokenIs(token, '..') ||
          tokenIs(token, '?..'))
        return false;
      if (tokenIs(token, '<')) {
        var look = Parser(parser.tokens, position, 0, parser.paths);
        if (parserLookTypeArguments(look) &&
            look.pendingClosers == 0 &&
            !look.pendingEquals &&
            (parserIs(look, '(') || parserIs(look, '.'))) {
          position = look.position;
          continue;
        }
      }
      if (tokenIs(token, 'as') || tokenIs(token, 'is')) {
        var start = position + 1;
        if (tokenIs(parser.tokens[start], '!')) start++;
        var look = Parser(parser.tokens, start, 0, parser.paths);
        if (parserLookType(look)) {
          if (tokenIs(parser.tokens[look.position - 1], '?') &&
              !parserNullableTypeEnd(look))
            look.position--;
          position = look.position;
          continue;
        }
      }
      if (tokenIs(token, '?') &&
          parserExpressionStart(parser.tokens[position + 1]))
        questions++;
      if (tokenIs(token, ':')) {
        if (questions == 0) return true;
        questions--;
      }
    }
    position++;
  }
  return false;
}

bool parserExpressionStart(Token token) {
  if (token.kind == tokenInteger ||
      token.kind == tokenString ||
      token.kind == tokenStringPart)
    return true;
  if (token.kind == tokenIdentifier) {
    return !tokenIsReserved(token) ||
        tokenIs(token, 'this') ||
        tokenIs(token, 'super') ||
        tokenIs(token, 'new') ||
        tokenIs(token, 'const') ||
        tokenIs(token, 'null') ||
        tokenIs(token, 'true') ||
        tokenIs(token, 'false') ||
        tokenIs(token, 'throw');
  }
  return tokenIs(token, '(') ||
      tokenIs(token, '[') ||
      tokenIs(token, '{') ||
      tokenIs(token, '<') ||
      tokenIs(token, '-') ||
      tokenIs(token, '!') ||
      tokenIs(token, '~') ||
      tokenIs(token, '++') ||
      tokenIs(token, '--');
}

AstExpression parserCascadeSection(Parser parser) {
  var token = parser.position;
  var receiver = parserImplicitReceiver(token);
  AstExpression section;
  var disposition = astCallValue;
  if (parserTake(parser, '[')) {
    var index = parseExpression(parser);
    parserExpect(parser, ']');
    section = AstExpression(
      astIndex,
      '[]',
      <AstExpression>[receiver, index],
      const <AstType>[],
      token,
    );
  } else {
    section = AstExpression(
      astMember,
      parserName(parser),
      <AstExpression>[receiver],
      const <AstType>[],
      token,
    );
    disposition = astCallSelector;
  }
  section = parserSelectors(parser, section, disposition, false);
  var op = parserPeek(parser);
  if (parser.tokens[parser.position].kind == tokenSymbol &&
      parserAssignment(op)) {
    var assignment = parser.position++;
    section = AstExpression(
      astAssignment,
      op,
      <AstExpression>[section, parseExpression(parser, false)],
      const <AstType>[],
      assignment,
    );
    section = parserContinueNullAware(section);
  }
  return section;
}

AstExpression parseExpression(Parser parser, [bool allowCascade = true]) {
  var expression = parserIfNull(parser);
  var token = parser.position;
  if (parserTake(parser, '?')) {
    var yes = parseExpression(parser, false);
    parserExpect(parser, ':');
    var no = parseExpression(parser, false);
    expression = AstExpression(
      astConditional,
      '?',
      <AstExpression>[expression, yes, no],
      <AstType>[],
      token,
    );
  }
  var op = parserPeek(parser);
  if (parser.tokens[parser.position].kind == tokenSymbol &&
      parserAssignment(op)) {
    var assignment = parser.position;
    parser.position++;
    var value = parseExpression(parser, allowCascade);
    expression = AstExpression(
      astAssignment,
      op,
      <AstExpression>[expression, value],
      <AstType>[],
      assignment,
    );
    expression = parserContinueNullAware(expression);
  } else if (allowCascade &&
      (parserIs(parser, '..') || parserIs(parser, '?..'))) {
    var cascade = parser.position++;
    var sections = <AstExpression>[expression, parserCascadeSection(parser)];
    while (parserTake(parser, '..'))
      sections.add(parserCascadeSection(parser));
    expression = AstExpression(
      astCascade,
      parser.tokens[cascade].text,
      sections,
      const <AstType>[],
      cascade,
    );
  }
  return expression;
}

AstType parserInferredType(int token) {
  return AstType('', const <AstType>[], token);
}

int parserDeclarationTypeEnd(Parser parser) {
  if (parserIs(parser, 'new')) return -1;
  var position = parser.position;
  var closers = parser.pendingClosers;
  var equals = parser.pendingEquals;
  var typed = parserLookType(parser, true);
  if (typed) {
    typed =
        parser.pendingClosers == 0 &&
        !parser.pendingEquals &&
        parser.tokens[parser.position].kind == tokenIdentifier &&
        !parserIs(parser, 'in') &&
        !parserIs(parser, 'is') &&
        !parserIs(parser, 'as') &&
        !tokenIs(parser.tokens[parser.position + 1], ':');
  }
  var end = -1;
  if (typed) end = parser.position;
  parser.position = position;
  parser.pendingClosers = closers;
  parser.pendingEquals = equals;
  return end;
}

bool parserTypedDeclaration(Parser parser) {
  return parserDeclarationTypeEnd(parser) >= 0;
}

String parserModifier(Parser parser) {
  if (parserTake(parser, 'var')) return 'var';
  if (parserTake(parser, 'final')) {
    if (parserIs(parser, 'var')) {
      parserError(parser, 'final cannot be combined with var');
    }
    return 'final';
  }
  if (parserTake(parser, 'const')) return 'const';
  return '';
}

AstType parserDeclarationType(Parser parser, String modifier) {
  if (modifier != 'var') {
    var end = parserDeclarationTypeEnd(parser);
    if (end >= 0) return parseAstType(parser, end);
  }
  return parserInferredType(parser.position);
}

List<AstVariable> parserVariablesRest(
  Parser parser,
  AstType type,
  String name,
  String modifier,
  int token,
  List<AstExpression> metadata,
) {
  var variable = parserVariableInitializer(parser, type, name, modifier, token);
  variable.metadata = metadata;
  var variables = parserVariableTail(parser, variable);
  parserExpect(parser, ';');
  return variables;
}

AstVariable parserVariableInitializer(
  Parser parser,
  AstType type,
  String name,
  String modifier,
  int token,
) {
  List<AstExpression> initializer = <AstExpression>[];
  if (parserTake(parser, '=')) initializer.add(parseExpression(parser));
  return AstVariable(type, name, initializer, modifier, token);
}

List<AstVariable> parserVariables(Parser parser) {
  var metadata = parserMetadata(parser);
  if (metadata.isNotEmpty && !parserVariableStatement(parser))
    parserError(parser, 'metadata must precede a local declaration');
  var token = parser.position;
  var modifier = parserModifier(parser);
  var type = parserDeclarationType(parser, modifier);
  var name = parserName(parser);
  return parserVariablesRest(parser, type, name, modifier, token, metadata);
}

List<AstParameter> parserParameters(Parser parser) {
  parserExpect(parser, '(');
  List<AstParameter> parameters = <AstParameter>[];
  var kind = astRequiredPositional;
  var close = ')';
  while (!parserIs(parser, close)) {
    if (kind == astRequiredPositional &&
        (parserIs(parser, '[') || parserIs(parser, '{'))) {
      kind = astOptionalPositional;
      close = ']';
      if (parserTake(parser, '{')) {
        kind = astNamedParameter;
        close = '}';
      } else {
        parserExpect(parser, '[');
      }
      if (parserIs(parser, close)) {
        parserError(parser, 'optional parameter group cannot be empty');
      }
    }
    var metadata = parserMetadata(parser);
    var token = parser.position;
    var required = false;
    if (parserIs(parser, 'required')) {
      var next = parser.tokens[parser.position + 1];
      if (!tokenIs(next, ',') &&
          !tokenIs(next, ')') &&
          !tokenIs(next, ']') &&
          !tokenIs(next, '}') &&
          !tokenIs(next, '=')) {
        if (kind != astNamedParameter) {
          parserError(parser, 'required needs a named parameter');
        }
        parser.position++;
        required = true;
      }
    }
    if (parserIs(parser, 'final') || parserIs(parser, 'const')) {
      parserError(parser, 'parameters cannot have final or const modifiers');
    }
    var type = parserDeclarationType(parser, '');
    var fieldFormal = parserTake(parser, 'this');
    var name = '';
    if (fieldFormal) {
      parserExpect(parser, '.');
      name = parserName(parser);
    } else {
      name = parserName(parser);
    }
    var parameter = AstParameter(type, name, fieldFormal, token);
    parameter.metadata = metadata;
    parameter.kind = kind;
    parameter.required = required;
    if (parserIs(parser, '=')) {
      if (kind == astRequiredPositional || required) {
        parserError(parser, 'required parameter cannot have a default value');
      }
      parser.position++;
      parameter.defaultValue = parseExpression(parser);
    }
    parameters.add(parameter);
    if (!parserTake(parser, ',')) break;
  }
  if (kind != astRequiredPositional) parserExpect(parser, close);
  parserExpect(parser, ')');
  return parameters;
}

AstInitializer parserInitializer(Parser parser) {
  var token = parser.position;
  if (parserTake(parser, 'assert')) {
    parserExpect(parser, '(');
    var condition = parseExpression(parser);
    AstExpression? message;
    if (parserTake(parser, ',') && !parserIs(parser, ')')) {
      message = parseExpression(parser);
      parserTake(parser, ',');
    }
    parserExpect(parser, ')');
    var initializer = AstInitializer(
      astAssertInitializer,
      '',
      condition,
      token,
    );
    initializer.message = message;
    return initializer;
  }
  var name = '';
  if (parserIs(parser, 'this') || parserIs(parser, 'super')) {
    var receiver = parserPeek(parser);
    parser.position++;
    var member = parser.position;
    if (parserTake(parser, '.')) {
      member = parser.position;
      name = parserName(parser);
    }
    if (receiver == 'super' || parserIs(parser, '(')) {
      var callee = AstExpression(
        astName,
        receiver,
        const <AstExpression>[],
        const <AstType>[],
        token,
      );
      if (name != '') {
        callee = AstExpression(
          astMember,
          name,
          <AstExpression>[callee],
          const <AstType>[],
          member,
        );
      }
      var call = parserCall(
        parser,
        callee,
        token,
        const <AstType>[],
        name == '' ? astCallIdentifier : astCallSelector,
      );
      var kind = astSuperInitializer;
      if (receiver == 'this') kind = astRedirectInitializer;
      return AstInitializer(kind, '', call, token);
    }
    if (name == '') parserError(parser, 'expected constructor invocation');
  } else {
    name = parserName(parser);
  }
  parserExpect(parser, '=');
  var expressionStart = parser.position;
  var expression = parseExpression(parser);
  if (expression.kind == astFunctionExpression &&
      expression.token == expressionStart)
    parserError(parser, 'initializer function expression requires parentheses');
  return AstInitializer(astFieldInitializer, name, expression, token);
}

List<AstInitializer> parserInitializers(Parser parser) {
  parserExpect(parser, ':');
  var result = <AstInitializer>[];
  while (true) {
    var initializer = parserInitializer(parser);
    if (initializer.kind == astRedirectInitializer && result.isNotEmpty)
      parserError(parser, 'redirect cannot have other initializers');
    result.add(initializer);
    if (!parserTake(parser, ',')) break;
    if (initializer.kind == astRedirectInitializer)
      parserError(parser, 'redirect cannot have other initializers');
  }
  return result;
}

AstFunction parserFunction(
  Parser parser,
  String name,
  AstType result,
  bool external,
  int token,
  bool getter,
  bool setter,
  bool constant, [
  bool constructor = false,
]) {
  if ((getter || setter) && parserIs(parser, '<')) {
    parserError(parser, 'accessors cannot have type parameters');
  }
  if (getter && parserIs(parser, '(')) {
    parserError(parser, 'getters cannot have parameters');
  }
  if (parserIs(parser, '<'))
    parserError(parser, 'generic function declarations are unsupported');
  List<AstParameter> parameters = <AstParameter>[];
  if (!getter) parameters = parserParameters(parser);
  if (setter) {
    if (result.name != '' &&
        (result.name != 'void' || result.arguments.isNotEmpty)) {
      parserError(parser, 'setter result must be void');
    }
    if (parameters.length != 1 ||
        parameters[0].kind != astRequiredPositional ||
        parameters[0].fieldFormal) {
      parserError(parser, 'setter requires one positional parameter');
    }
    if (result.name == '') result = AstType('void', <AstType>[], token);
  }
  List<AstInitializer> initializers = const <AstInitializer>[];
  if (parserIs(parser, ':')) {
    if (!constructor || external)
      parserError(parser, 'initializer list requires a generative constructor');
    initializers = parserInitializers(parser);
  }
  if (initializers.isNotEmpty &&
      initializers[0].kind == astRedirectInitializer &&
      !parserIs(parser, ';'))
    parserError(parser, 'redirecting constructor cannot have a body');
  if (constructor && parserIs(parser, '=>'))
    parserError(parser, 'generative constructor cannot have an arrow body');
  if (constant && !parserIs(parser, ';'))
    parserError(parser, 'const constructor cannot have a body');
  AstStatement? body;
  AstExpression? arrow;
  if (parserTake(parser, '=>')) {
    arrow = parseExpression(parser);
    parserExpect(parser, ';');
  } else if (!parserTake(parser, ';')) {
    if (!parserIs(parser, '{')) parserError(parser, 'expected function body');
    body = parseStatement(parser);
  }
  var function = AstFunction(
    name,
    result,
    parameters,
    body,
    arrow,
    external,
    token,
    getter,
  );
  function.setter = setter;
  function.constant = constant;
  function.initializers = initializers;
  return function;
}

bool parserConstructorAhead(Parser parser, String name) {
  if (!parserIs(parser, name)) return false;
  var position = parser.position;
  if (tokenIs(parser.tokens[position + 1], '(')) return true;
  return tokenIs(parser.tokens[position + 1], '.') &&
      parser.tokens[position + 2].kind == tokenIdentifier &&
      tokenIs(parser.tokens[position + 3], '(');
}

AstClass parserClass(Parser parser, int token) {
  var name = parserTypeDeclarationName(parser);
  parserExpect(parser, '{');
  List<AstVariable> fields = <AstVariable>[];
  List<AstVariable>? staticFields;
  List<AstFunction> constructors = <AstFunction>[];
  List<AstFunction> methods = <AstFunction>[];
  while (!parserIs(parser, '}')) {
    var metadata = parserMetadata(parser);
    var memberToken = parser.position;
    var external = parserTake(parser, 'external');
    var isStatic = false;
    if (parserIs(parser, 'static')) {
      var next = parser.tokens[parser.position + 1];
      if (!tokenIs(next, '(') &&
          !tokenIs(next, '=') &&
          !tokenIs(next, ',') &&
          !tokenIs(next, ';')) {
        parser.position++;
        isStatic = true;
      }
    }
    var constant = parserTake(parser, 'const');
    if (parserConstructorAhead(parser, name)) {
      if (isStatic) parserError(parser, 'constructors cannot be static');
      if (external)
        parserError(parser, 'external constructors are unsupported');
      var constructorToken = parser.position;
      parser.position++;
      var constructorName = name;
      if (parserTake(parser, '.')) {
        if (tokenIsReserved(parser.tokens[parser.position]) &&
            !parserIs(parser, 'new'))
          parserError(parser, 'reserved word cannot be a constructor name');
        constructorName += '.' + parserName(parser);
      }
      var constructor = parserFunction(
        parser,
        constructorName,
        parserInferredType(constructorToken),
        false,
        constructorToken,
        false,
        false,
        constant,
        true,
      );
      constructor.metadata = metadata;
      constructors.add(constructor);
    } else {
      if (constant && !isStatic)
        parserError(parser, 'const requires a constructor declaration');
      var modifier = 'const';
      if (!constant) modifier = parserModifier(parser);
      var getter =
          parserIs(parser, 'get') &&
          parser.tokens[parser.position + 1].kind == tokenIdentifier;
      var setter =
          parserIs(parser, 'set') &&
          parser.tokens[parser.position + 1].kind == tokenIdentifier;
      var type = parserInferredType(memberToken);
      if (!getter && !setter) type = parserDeclarationType(parser, modifier);
      var member = parserName(parser);
      if ((member == 'get' || member == 'set') &&
          parser.tokens[parser.position].kind == tokenIdentifier) {
        getter = member == 'get';
        setter = member == 'set';
        member = parserName(parser);
      }
      if (getter || setter || parserIs(parser, '(')) {
        if (constant)
          parserError(parser, 'const requires a constructor declaration');
        if (modifier != '') {
          parserError(parser, 'methods cannot have variable modifiers');
        }
        var method = parserFunction(
          parser,
          member,
          type,
          external,
          memberToken,
          getter,
          setter,
          false,
        );
        method.metadata = metadata;
        method.isStatic = isStatic;
        methods.add(method);
      } else {
        if (external) parserError(parser, 'external fields are not supported');
        var variables = parserVariablesRest(
          parser,
          type,
          member,
          modifier,
          memberToken,
          metadata,
        );
        var i = 0;
        while (i < variables.length) {
          if (isStatic)
            (staticFields ??= <AstVariable>[]).add(variables[i]);
          else
            fields.add(variables[i]);
          i++;
        }
      }
    }
  }
  parserExpect(parser, '}');
  var result = AstClass(name, fields, constructors, methods, token);
  if (staticFields != null) result.staticFields = staticFields;
  return result;
}

List<AstTypeParameter> parserTypeParameters(Parser parser) {
  parserExpect(parser, '<');
  var result = <AstTypeParameter>[];
  while (true) {
    var metadata = parserMetadata(parser);
    var token = parser.position;
    var name = parserTypeDeclarationName(parser);
    AstType? bound;
    if (parserTake(parser, 'extends')) {
      bound = parseAstType(parser);
      if (bound.name == 'void' || bound.name == 'void?')
        parserError(parser, 'type parameter bound cannot be void');
    }
    var parameter = AstTypeParameter(name, bound, token);
    parameter.metadata = metadata;
    result.add(parameter);
    if (!parserTake(parser, ',')) break;
  }
  if (!parserTypeClose(parser)) parserError(parser, 'expected >');
  return result;
}

AstTypedef parserTypedef(Parser parser, int token) {
  var returnType = parserDeclarationType(parser, '');
  var name = parserTypeDeclarationName(parser);
  var typeParameters = const <AstTypeParameter>[];
  if (parserIs(parser, '<')) typeParameters = parserTypeParameters(parser);
  AstType type;
  if (parserTake(parser, '=')) {
    if (returnType.name != '')
      parserError(parser, 'modern typedef cannot have a return type prefix');
    type = parseAstType(parser);
  } else {
    if (returnType.name == '')
      returnType = AstType('dynamic', const <AstType>[], token);
    type = AstType('Function', const <AstType>[], returnType.token);
    type.function = AstFunctionType(
      returnType,
      parserFunctionTypeParameters(parser, true),
    );
  }
  parserExpect(parser, ';');
  var result = AstTypedef(name, type, token);
  result.typeParameters = typeParameters;
  return result;
}

String parserUriName(Parser parser) {
  if (tokenIsReserved(parser.tokens[parser.position]))
    parserError(parser, 'reserved word cannot be a URI test identifier');
  return parserName(parser);
}

String parserUriString(Parser parser) {
  if (parser.tokens[parser.position].kind != tokenString)
    parserError(parser, 'expected URI string without interpolation');
  var text = parser.tokens[parser.position].text;
  parser.position++;
  while (parser.tokens[parser.position].kind == tokenString) {
    text += parser.tokens[parser.position].text;
    parser.position++;
  }
  if (parser.tokens[parser.position].kind == tokenStringPart)
    parserError(parser, 'URI strings cannot contain interpolation');
  return text;
}

bool parserPartDirective(Parser parser) {
  if (!parserIs(parser, 'part')) return false;
  var next = parser.tokens[parser.position + 1];
  return next.kind == tokenString ||
      next.kind == tokenStringPart ||
      tokenIs(next, 'of');
}

AstDirective parserDirective(Parser parser, int kind, int token) {
  var uri = '';
  var prefix = '';
  var combinators = <AstCombinator>[];
  List<AstConditionalUri>? conditions;
  if (kind == astLibraryDirective || kind == astPartOfNameDirective) {
    if (kind == astPartOfNameDirective || !parserIs(parser, ';')) {
      uri = parserName(parser);
      while (parserTake(parser, '.')) uri = uri + '.' + parserName(parser);
    }
  } else if (kind == astPartDirective || kind == astPartOfUriDirective) {
    uri = parserUriString(parser);
  } else {
    uri = parserUriString(parser);
    while (parserTake(parser, 'if')) {
      var conditionToken = parser.position - 1;
      parserExpect(parser, '(');
      var key = parserUriName(parser);
      while (parserTake(parser, '.')) key += '.' + parserUriName(parser);
      var value = 'true';
      if (parserTake(parser, '==')) value = parserUriString(parser);
      parserExpect(parser, ')');
      var alternative = parserUriString(parser);
      conditions ??= <AstConditionalUri>[];
      conditions.add(
        AstConditionalUri(key, value, alternative, conditionToken),
      );
    }
    if (kind == astImportDirective && parserTake(parser, 'as')) {
      prefix = parserName(parser);
    }
    while (parserIs(parser, 'show') || parserIs(parser, 'hide')) {
      var show = parserTake(parser, 'show');
      if (!show) parserExpect(parser, 'hide');
      var names = <String>[parserName(parser)];
      while (parserTake(parser, ',')) names.add(parserName(parser));
      combinators.add(AstCombinator(show, names));
    }
  }
  parserExpect(parser, ';');
  var directive = AstDirective(kind, uri, prefix, token, combinators);
  if (conditions != null) directive.conditions = conditions;
  return directive;
}

AstUnit parseUnit(Parser parser) {
  var unit = AstUnit(
    <AstDirective>[],
    <AstVariable>[],
    <AstFunction>[],
    <AstClass>[],
    <AstTypedef>[],
  );
  var source = -1;
  var declarations = false;
  while (!parserIs(parser, '')) {
    var metadata = parserMetadata(parser);
    var token = parser.position;
    if (parser.tokens[token].source != source) {
      source = parser.tokens[token].source;
      declarations = false;
    }
    if (parserIs(parser, 'import') ||
        parserIs(parser, 'export') ||
        parserIs(parser, 'library') ||
        parserPartDirective(parser)) {
      if (declarations)
        parserError(parser, 'directives must precede declarations');
    } else {
      declarations = true;
    }
    if (parserTake(parser, 'import')) {
      var directive = parserDirective(parser, astImportDirective, token);
      directive.metadata = metadata;
      unit.directives.add(directive);
    } else if (parserTake(parser, 'export')) {
      var directive = parserDirective(parser, astExportDirective, token);
      directive.metadata = metadata;
      unit.directives.add(directive);
    } else if (parserTake(parser, 'library')) {
      var directive = parserDirective(parser, astLibraryDirective, token);
      directive.metadata = metadata;
      unit.directives.add(directive);
    } else if (parserPartDirective(parser)) {
      parser.position++;
      var kind = astPartDirective;
      if (parserTake(parser, 'of')) {
        kind = astPartOfNameDirective;
        if (parser.tokens[parser.position].kind == tokenString ||
            parser.tokens[parser.position].kind == tokenStringPart)
          kind = astPartOfUriDirective;
      }
      var directive = parserDirective(parser, kind, token);
      directive.metadata = metadata;
      unit.directives.add(directive);
    } else if (parserTake(parser, 'class')) {
      var syntax = parserClass(parser, token);
      syntax.metadata = metadata;
      unit.classes.add(syntax);
    } else if (parserTake(parser, 'typedef')) {
      var syntax = parserTypedef(parser, token);
      syntax.metadata = metadata;
      unit.typedefs.add(syntax);
    } else {
      var external = parserTake(parser, 'external');
      var modifier = parserModifier(parser);
      var getter =
          parserIs(parser, 'get') &&
          parser.tokens[parser.position + 1].kind == tokenIdentifier;
      var setter =
          parserIs(parser, 'set') &&
          parser.tokens[parser.position + 1].kind == tokenIdentifier;
      var type = parserInferredType(token);
      if (!getter && !setter) type = parserDeclarationType(parser, modifier);
      var name = parserName(parser);
      if ((name == 'get' || name == 'set') &&
          parser.tokens[parser.position].kind == tokenIdentifier) {
        getter = name == 'get';
        setter = name == 'set';
        name = parserName(parser);
      }
      if (getter || setter || parserIs(parser, '(')) {
        if (modifier == 'const')
          parserError(parser, 'const requires a constructor declaration');
        if ((getter || setter) && modifier != '') {
          parserError(parser, 'accessors cannot have variable modifiers');
        }
        var function = parserFunction(
          parser,
          name,
          type,
          external,
          token,
          getter,
          setter,
          false,
        );
        function.metadata = metadata;
        unit.functions.add(function);
      } else {
        if (external)
          parserError(parser, 'external variables are not supported');
        var variables = parserVariablesRest(
          parser,
          type,
          name,
          modifier,
          token,
          metadata,
        );
        var i = 0;
        while (i < variables.length) {
          unit.variables.add(variables[i]);
          i++;
        }
      }
    }
  }
  return unit;
}

AstStatement parserEmptyStatement(int token) {
  return AstStatement(
    astEmptyStatement,
    <AstExpression>[],
    <AstStatement>[],
    <AstVariable>[],
    <AstExpression>[],
    <AstExpression>[],
    token,
  );
}

bool parserVariableStatement(Parser parser) {
  if (parserIs(parser, 'const')) {
    var position = parser.position;
    parser.position++;
    var declaration = parserTypedDeclaration(parser);
    if (!declaration &&
        parser.tokens[parser.position].kind == tokenIdentifier) {
      var next = parser.tokens[parser.position + 1];
      declaration =
          tokenIs(next, '=') || tokenIs(next, ',') || tokenIs(next, ';');
    }
    parser.position = position;
    return declaration;
  }
  return parserIs(parser, 'var') ||
      parserIs(parser, 'final') ||
      parserTypedDeclaration(parser);
}

bool parserUntypedFunction(Parser parser) {
  var position = parser.position;
  return parser.tokens[position].kind == tokenIdentifier &&
      parserFunctionAhead(parser, position + 1);
}

AstStatement parseStatement(Parser parser) {
  var token = parser.position;
  if (parser.tokens[parser.position].kind == tokenIdentifier &&
      parser.tokens[parser.position + 1].kind == tokenSymbol &&
      parser.tokens[parser.position + 1].text == ':') {
    var name = parserName(parser);
    parserExpect(parser, ':');
    var label = AstExpression(
      astName,
      name,
      <AstExpression>[],
      <AstType>[],
      token,
    );
    return AstStatement(
      astLabeledStatement,
      <AstExpression>[label],
      <AstStatement>[parseStatement(parser)],
      <AstVariable>[],
      <AstExpression>[],
      <AstExpression>[],
      token,
    );
  }
  if (parserTake(parser, '{')) {
    List<AstStatement> children = <AstStatement>[];
    while (!parserIs(parser, '}')) children.add(parseStatement(parser));
    parserExpect(parser, '}');
    return AstStatement(
      astBlockStatement,
      <AstExpression>[],
      children,
      <AstVariable>[],
      <AstExpression>[],
      <AstExpression>[],
      token,
    );
  }
  if (parserTake(parser, ';')) return parserEmptyStatement(token);
  if (parserTake(parser, 'return')) {
    List<AstExpression> values = <AstExpression>[];
    if (!parserIs(parser, ';')) values.add(parseExpression(parser));
    parserExpect(parser, ';');
    return AstStatement(
      astReturnStatement,
      values,
      <AstStatement>[],
      <AstVariable>[],
      <AstExpression>[],
      <AstExpression>[],
      token,
    );
  }
  if (parserTake(parser, 'if')) {
    parserExpect(parser, '(');
    List<AstExpression> condition = <AstExpression>[parseExpression(parser)];
    parserExpect(parser, ')');
    List<AstStatement> children = <AstStatement>[parseStatement(parser)];
    if (parserTake(parser, 'else')) children.add(parseStatement(parser));
    return AstStatement(
      astIfStatement,
      <AstExpression>[],
      children,
      <AstVariable>[],
      condition,
      <AstExpression>[],
      token,
    );
  }
  if (parserTake(parser, 'while')) {
    parserExpect(parser, '(');
    List<AstExpression> condition = <AstExpression>[parseExpression(parser)];
    parserExpect(parser, ')');
    List<AstStatement> children = <AstStatement>[parseStatement(parser)];
    return AstStatement(
      astWhileStatement,
      <AstExpression>[],
      children,
      <AstVariable>[],
      condition,
      <AstExpression>[],
      token,
    );
  }
  if (parserTake(parser, 'switch')) return parserSwitch(parser, token);
  if (parserTake(parser, 'do')) {
    var body = parseStatement(parser);
    parserExpect(parser, 'while');
    parserExpect(parser, '(');
    var condition = parseExpression(parser);
    parserExpect(parser, ')');
    parserExpect(parser, ';');
    return AstStatement(
      astDoWhileStatement,
      <AstExpression>[],
      <AstStatement>[body],
      <AstVariable>[],
      <AstExpression>[condition],
      <AstExpression>[],
      token,
    );
  }
  if (parserTake(parser, 'for')) return parserFor(parser, token, false);
  if (parserTake(parser, 'break')) {
    var labels = parserJumpLabel(parser);
    parserExpect(parser, ';');
    return AstStatement(
      astBreakStatement,
      labels,
      <AstStatement>[],
      <AstVariable>[],
      <AstExpression>[],
      <AstExpression>[],
      token,
    );
  }
  if (parserTake(parser, 'continue')) {
    var labels = parserJumpLabel(parser);
    parserExpect(parser, ';');
    return AstStatement(
      astContinueStatement,
      labels,
      <AstStatement>[],
      <AstVariable>[],
      <AstExpression>[],
      <AstExpression>[],
      token,
    );
  }
  if (parserIs(parser, '@') ||
      parserVariableStatement(parser) ||
      parserUntypedFunction(parser)) {
    var metadata = parserMetadata(parser);
    var declaration = parser.position;
    var modifier = parserModifier(parser);
    var type = parserDeclarationType(parser, modifier);
    var name = parserName(parser);
    if (modifier == '' && parserIs(parser, '(')) {
      var function = parserFunction(
        parser,
        name,
        type,
        false,
        declaration,
        false,
        false,
        false,
      );
      if (function.body == null && function.arrow == null)
        parserError(parser, 'local function requires a body');
      function.metadata = metadata;
      var statement = parserEmptyStatement(token);
      statement.kind = astLocalFunctionStatement;
      statement.function = function;
      return statement;
    }
    return AstStatement(
      astVariableStatement,
      <AstExpression>[],
      <AstStatement>[],
      parserVariablesRest(parser, type, name, modifier, declaration, metadata),
      <AstExpression>[],
      <AstExpression>[],
      token,
    );
  }
  var expression = parseExpression(parser);
  parserExpect(parser, ';');
  return AstStatement(
    astExpressionStatement,
    <AstExpression>[expression],
    <AstStatement>[],
    <AstVariable>[],
    <AstExpression>[],
    <AstExpression>[],
    token,
  );
}

AstStatement parserSwitch(Parser parser, int token) {
  parserExpect(parser, '(');
  var value = parseExpression(parser);
  parserExpect(parser, ')');
  parserExpect(parser, '{');
  List<AstStatement> cases = <AstStatement>[];
  while (!parserIs(parser, '}')) {
    var caseToken = parser.position;
    List<AstExpression> pattern = <AstExpression>[];
    if (parserTake(parser, 'case')) {
      pattern.add(parseExpression(parser));
    } else {
      parserExpect(parser, 'default');
    }
    parserExpect(parser, ':');
    List<AstStatement> body = <AstStatement>[];
    while (!parserIs(parser, 'case') &&
        !parserIs(parser, 'default') &&
        !parserIs(parser, '}')) {
      body.add(parseStatement(parser));
    }
    cases.add(
      AstStatement(
        astSwitchCaseStatement,
        pattern,
        body,
        <AstVariable>[],
        <AstExpression>[],
        <AstExpression>[],
        caseToken,
      ),
    );
  }
  parserExpect(parser, '}');
  return AstStatement(
    astSwitchStatement,
    <AstExpression>[value],
    cases,
    <AstVariable>[],
    <AstExpression>[],
    <AstExpression>[],
    token,
  );
}

List<AstExpression> parserJumpLabel(Parser parser) {
  List<AstExpression> labels = <AstExpression>[];
  if (parser.tokens[parser.position].kind == tokenIdentifier) {
    var token = parser.position;
    var name = parserName(parser);
    labels.add(
      AstExpression(astName, name, <AstExpression>[], <AstType>[], token),
    );
  }
  return labels;
}

List<AstVariable> parserVariableTail(Parser parser, AstVariable first) {
  List<AstVariable> variables = <AstVariable>[first];
  while (parserTake(parser, ',')) {
    var token = parser.position;
    var name = parserName(parser);
    var variable = parserVariableInitializer(
      parser,
      first.type,
      name,
      first.modifier,
      token,
    );
    variable.metadata = first.metadata;
    variables.add(variable);
  }
  return variables;
}

AstExpression parserString(Parser parser) {
  var token = parser.position;
  List<AstExpression> parts = <AstExpression>[];
  var interpolated = false;
  while (parser.tokens[parser.position].kind == tokenString ||
      parser.tokens[parser.position].kind == tokenStringPart) {
    var plain = parser.tokens[parser.position].kind == tokenString;
    while (true) {
      var part = parser.tokens[parser.position];
      parts.add(
        AstExpression(
          astString,
          part.text,
          <AstExpression>[],
          <AstType>[],
          parser.position,
        ),
      );
      parser.position++;
      if (plain || part.kind == tokenStringTail) break;
      interpolated = true;
      if (parser.tokens[parser.position].kind != tokenInterpolationStart) {
        parserError(parser, 'expected interpolation');
      }
      parser.position++;
      parts.add(parseExpression(parser));
      if (parser.tokens[parser.position].kind != tokenInterpolationEnd) {
        parserError(parser, 'expected end of interpolation');
      }
      parser.position++;
    }
  }
  if (interpolated)
    return AstExpression(astInterpolation, '', parts, <AstType>[], token);
  var text = '';
  var i = 0;
  while (i < parts.length) {
    text = text + parts[i].text;
    i++;
  }
  return AstExpression(astString, text, <AstExpression>[], <AstType>[], token);
}
