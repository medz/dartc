import 'ast.dart';
import 'host.dart';
import 'scanner.dart';

class Parser {
  List<Token> tokens;
  int position;
  int pendingClosers;
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
  return parser.tokens[parser.position].text;
}

bool parserIs(Parser parser, String text) {
  if (parser.pendingClosers > 0) return text == '>';
  return tokenIs(parser.tokens[parser.position], text);
}

bool parserTake(Parser parser, String text) {
  if (!parserIs(parser, text)) return false;
  if (parser.pendingClosers > 0)
    parser.pendingClosers--;
  else
    parser.position++;
  return true;
}

void parserExpect(Parser parser, String text) {
  if (!parserTake(parser, text)) parserError(parser, 'expected ' + text);
}

String parserName(Parser parser) {
  if (parser.pendingClosers != 0 ||
      parser.tokens[parser.position].kind != tokenIdentifier) {
    parserError(parser, 'expected identifier');
  }
  var name = parserPeek(parser);
  parser.position++;
  return name;
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
  return false;
}

bool parserLookType(Parser parser, [bool declaration = false]) {
  if (parser.pendingClosers != 0 ||
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
      return result;
    }
    result = true;
  }
  return result;
}

bool parserHasTypeArguments(Parser parser, bool invocation) {
  var position = parser.position;
  var closers = parser.pendingClosers;
  var valid = parserTake(parser, '<');
  if (valid) valid = parserLookType(parser);
  while (valid && parserTake(parser, ',')) valid = parserLookType(parser);
  if (valid) valid = parserTypeClose(parser);
  if (valid && invocation) {
    valid =
        parser.pendingClosers == 0 &&
        (parserIs(parser, '(') || parserIs(parser, '.'));
  }
  parser.position = position;
  parser.pendingClosers = closers;
  return valid;
}

List<AstParameter> parserFunctionTypeParameters(Parser parser) {
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
    var required = parserTake(parser, 'required');
    if (required && kind != astNamedParameter)
      parserError(parser, 'required needs a named parameter');
    if (parserIs(parser, 'final') ||
        parserIs(parser, 'const') ||
        parserIs(parser, 'this') ||
        parserIs(parser, 'super')) {
      parserError(parser, 'invalid function type parameter');
    }
    var type = parseAstType(parser);
    var name = '';
    if (parser.tokens[parser.position].kind == tokenIdentifier)
      name = parserName(parser);
    if (kind == astNamedParameter && name == '')
      parserError(parser, 'named function type parameter requires a name');
    if (parserIs(parser, '='))
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
    children.add(parseExpression(parser));
    if (!parserTake(parser, ',')) break;
  }
  parserExpect(parser, ']');
  return AstExpression(astList, '', children, arguments, token);
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
  var body = <AstStatement>[];
  var arrow = <AstExpression>[];
  if (parserTake(parser, '=>'))
    arrow.add(parseExpression(parser));
  else {
    if (!parserIs(parser, '{'))
      parserError(parser, 'expected function expression body');
    body.add(parseStatement(parser));
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
    value = parserCall(parser, value, token, arguments);
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
  while (true) {
    var token = parser.position;
    if (parserIs(parser, '<') && parserHasTypeArguments(parser, true)) {
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
        parserTake(parser, '++') ||
        parserTake(parser, '--')) {
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
    return AstExpression(
      astUnary,
      op,
      <AstExpression>[parserUnary(parser)],
      <AstType>[],
      token,
    );
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

AstExpression parseExpression(Parser parser) {
  var expression = parserIfNull(parser);
  var token = parser.position;
  if (parserTake(parser, '?')) {
    var yes = parseExpression(parser);
    parserExpect(parser, ':');
    var no = parseExpression(parser);
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
    var value = parseExpression(parser);
    expression = AstExpression(
      astAssignment,
      op,
      <AstExpression>[expression, value],
      <AstType>[],
      assignment,
    );
  }
  return expression;
}

AstType parserInferredType(int token) {
  return AstType('', const <AstType>[], token);
}

int parserDeclarationTypeEnd(Parser parser) {
  var position = parser.position;
  var closers = parser.pendingClosers;
  var typed = parserLookType(parser, true);
  if (typed) {
    typed =
        parser.pendingClosers == 0 &&
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

AstFunction parserFunction(
  Parser parser,
  String name,
  AstType result,
  bool external,
  int token,
  bool getter,
  bool setter,
  bool constant,
) {
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
  if (parserIs(parser, ':'))
    parserError(parser, 'constructor initializer lists are unsupported');
  if (constant && !parserIs(parser, ';'))
    parserError(parser, 'const constructor cannot have a body');
  List<AstStatement> body = <AstStatement>[];
  List<AstExpression> arrow = <AstExpression>[];
  if (parserTake(parser, '=>')) {
    arrow.add(parseExpression(parser));
    parserExpect(parser, ';');
  } else if (!parserTake(parser, ';')) {
    if (!parserIs(parser, '{')) parserError(parser, 'expected function body');
    body.add(parseStatement(parser));
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
  return function;
}

AstClass parserClass(Parser parser, int token) {
  var name = parserName(parser);
  parserExpect(parser, '{');
  List<AstVariable> fields = <AstVariable>[];
  List<AstFunction> constructors = <AstFunction>[];
  List<AstFunction> methods = <AstFunction>[];
  while (!parserIs(parser, '}')) {
    var metadata = parserMetadata(parser);
    var memberToken = parser.position;
    var constant = parserTake(parser, 'const');
    if (parserIs(parser, name) &&
        parser.tokens[parser.position + 1].kind == tokenSymbol &&
        parser.tokens[parser.position + 1].text == '(') {
      parser.position++;
      var constructor = parserFunction(
        parser,
        name,
        parserInferredType(memberToken),
        false,
        memberToken,
        false,
        false,
        constant,
      );
      constructor.metadata = metadata;
      constructors.add(constructor);
    } else {
      if (constant)
        parserError(parser, 'const requires an unnamed constructor');
      var external = parserTake(parser, 'external');
      var modifier = parserModifier(parser);
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
        if ((getter || setter) && modifier != '') {
          parserError(parser, 'accessors cannot have variable modifiers');
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
          fields.add(variables[i]);
          i++;
        }
      }
    }
  }
  parserExpect(parser, '}');
  return AstClass(name, fields, constructors, methods, token);
}

AstTypedef parserTypedef(Parser parser, int token) {
  var name = parserName(parser);
  if (parserIs(parser, '<'))
    parserError(parser, 'generic type aliases are unsupported');
  parserExpect(parser, '=');
  var type = parseAstType(parser);
  parserExpect(parser, ';');
  return AstTypedef(name, type, token);
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
  if (parserTake(parser, 'for')) {
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
            <AstStatement>[parseStatement(parser)],
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
      parseStatement(parser),
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
      if (function.body.isEmpty && function.arrow.isEmpty)
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
