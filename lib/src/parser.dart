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

void parserError(Parser parser, String message) {
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

bool parserLookType(Parser parser) {
  if (parser.pendingClosers != 0 ||
      parser.tokens[parser.position].kind != tokenIdentifier)
    return false;
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
  return true;
}

bool parserHasTypeArguments(Parser parser) {
  var position = parser.position;
  var closers = parser.pendingClosers;
  var valid = parserTake(parser, '<');
  if (valid) valid = parserLookType(parser);
  while (valid && parserTake(parser, ',')) valid = parserLookType(parser);
  if (valid) valid = parserTypeClose(parser);
  if (valid) {
    valid =
        parser.pendingClosers == 0 &&
        (parserIs(parser, '(') || parserIs(parser, '.'));
  }
  parser.position = position;
  parser.pendingClosers = closers;
  return valid;
}

AstType parseAstType(Parser parser) {
  var token = parser.position;
  var name = parserName(parser);
  while (parserTake(parser, '.')) name = name + '.' + parserName(parser);
  List<AstType> arguments = <AstType>[];
  if (parserTake(parser, '<')) {
    arguments.add(parseAstType(parser));
    while (parserTake(parser, ',')) arguments.add(parseAstType(parser));
    if (!parserTypeClose(parser)) parserError(parser, 'expected >');
  }
  if (parserTake(parser, '?')) name = name + '?';
  return AstType(name, arguments, token);
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

AstExpression parserPrimary(Parser parser) {
  var token = parser.position;
  var current = parser.tokens[token];
  if (current.kind == tokenInteger) {
    parser.position++;
    return AstExpression(
      astInteger,
      current.text,
      <AstExpression>[],
      <AstType>[],
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
      <AstExpression>[],
      <AstType>[],
      token,
    );
  }
  if (parserTake(parser, 'null')) {
    return AstExpression(
      astNull,
      'null',
      <AstExpression>[],
      <AstType>[],
      token,
    );
  }
  if (parserTake(parser, '(')) {
    var expression = parseExpression(parser);
    parserExpect(parser, ')');
    return expression;
  }
  if (parserIs(parser, '[')) return parserList(parser, <AstType>[], token);
  if (parserTake(parser, '<')) {
    List<AstType> arguments = <AstType>[parseAstType(parser)];
    if (!parserTypeClose(parser)) parserError(parser, 'expected >');
    return parserList(parser, arguments, token);
  }
  var name = parserName(parser);
  return AstExpression(astName, name, <AstExpression>[], <AstType>[], token);
}

AstExpression parserCall(Parser parser, AstExpression callee, int token) {
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
  return AstExpression(astCall, '', children, <AstType>[], token);
}

AstExpression parserPostfix(Parser parser) {
  var expression = parserPrimary(parser);
  while (true) {
    var token = parser.position;
    if ((expression.kind == astName || expression.kind == astMember) &&
        parserIs(parser, '<') &&
        parserHasTypeArguments(parser)) {
      expression.typeArguments = parserTypeArguments(parser);
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
    } else if (parserIs(parser, '(')) {
      expression = parserCall(parser, expression, token);
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
    } else if (parserTake(parser, '++') || parserTake(parser, '--')) {
      expression = AstExpression(
        astPostfix,
        parser.tokens[token].text,
        <AstExpression>[expression],
        <AstType>[],
        token,
      );
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
      (op == '-' ||
          op == '+' ||
          op == '!' ||
          op == '~' ||
          op == '++' ||
          op == '--')) {
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
  if (op == '<' || op == '<=' || op == '>' || op == '>=') return 4;
  if (op == '|') return 5;
  if (op == '^') return 6;
  if (op == '&') return 7;
  if (op == '<<' || op == '>>' || op == '>>>') return 8;
  if (op == '+' || op == '-') return 9;
  if (op == '*' || op == '~/' || op == '%') return 10;
  return 0;
}

AstExpression parserBinary(Parser parser, int minimum) {
  var expression = parserUnary(parser);
  while (parser.tokens[parser.position].kind != tokenString &&
      parserPrecedence(parserPeek(parser)) >= minimum) {
    var token = parser.position;
    var op = parserPeek(parser);
    var precedence = parserPrecedence(op);
    parser.position++;
    var right = parserBinary(parser, precedence + 1);
    expression = AstExpression(
      astBinary,
      op,
      <AstExpression>[expression, right],
      <AstType>[],
      token,
    );
  }
  return expression;
}

bool parserAssignment(String op) {
  return op == '=' ||
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

AstExpression parseExpression(Parser parser) {
  var expression = parserBinary(parser, 1);
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
  return AstType('', <AstType>[], token);
}

bool parserTypedDeclaration(Parser parser) {
  var position = parser.position;
  var closers = parser.pendingClosers;
  var typed = parserLookType(parser);
  if (typed) {
    typed =
        parser.pendingClosers == 0 &&
        parser.tokens[parser.position].kind == tokenIdentifier &&
        !parserIs(parser, 'in') &&
        !tokenIs(parser.tokens[parser.position + 1], ':');
  }
  parser.position = position;
  parser.pendingClosers = closers;
  return typed;
}

String parserModifier(Parser parser) {
  if (parserTake(parser, 'var')) return 'var';
  if (parserTake(parser, 'final')) return 'final';
  if (parserTake(parser, 'const')) return 'const';
  return '';
}

AstType parserDeclarationType(Parser parser, String modifier) {
  if (modifier != 'var' && parserTypedDeclaration(parser)) {
    return parseAstType(parser);
  }
  return parserInferredType(parser.position);
}

List<AstVariable> parserVariablesRest(
  Parser parser,
  AstType type,
  String name,
  String modifier,
  int token,
) {
  var variable = parserVariableInitializer(parser, type, name, modifier, token);
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
  var token = parser.position;
  var modifier = parserModifier(parser);
  var type = parserDeclarationType(parser, modifier);
  var name = parserName(parser);
  return parserVariablesRest(parser, type, name, modifier, token);
}

List<AstParameter> parserParameters(Parser parser) {
  parserExpect(parser, '(');
  List<AstParameter> parameters = <AstParameter>[];
  while (!parserIs(parser, ')')) {
    var token = parser.position;
    var type = parserInferredType(token);
    var fieldFormal = parserTake(parser, 'this');
    var name = '';
    if (fieldFormal) {
      parserExpect(parser, '.');
      name = parserName(parser);
    } else {
      type = parserDeclarationType(parser, '');
      name = parserName(parser);
    }
    parameters.add(AstParameter(type, name, fieldFormal, token));
    if (!parserTake(parser, ',')) break;
  }
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
) {
  List<AstParameter> parameters = <AstParameter>[];
  if (!getter) parameters = parserParameters(parser);
  List<AstStatement> body = <AstStatement>[];
  List<AstExpression> arrow = <AstExpression>[];
  if (parserTake(parser, '=>')) {
    arrow.add(parseExpression(parser));
    parserExpect(parser, ';');
  } else if (!parserTake(parser, ';')) {
    if (!parserIs(parser, '{')) parserError(parser, 'expected function body');
    body.add(parseStatement(parser));
  }
  return AstFunction(
    name,
    result,
    parameters,
    body,
    arrow,
    external,
    token,
    getter,
  );
}

AstClass parserClass(Parser parser, int token) {
  var name = parserName(parser);
  parserExpect(parser, '{');
  List<AstVariable> fields = <AstVariable>[];
  List<AstFunction> constructors = <AstFunction>[];
  List<AstFunction> methods = <AstFunction>[];
  while (!parserIs(parser, '}')) {
    var memberToken = parser.position;
    if (parserIs(parser, name) &&
        parser.tokens[parser.position + 1].kind == tokenSymbol &&
        parser.tokens[parser.position + 1].text == '(') {
      parser.position++;
      constructors.add(
        parserFunction(
          parser,
          name,
          parserInferredType(memberToken),
          false,
          memberToken,
          false,
        ),
      );
    } else {
      var external = parserTake(parser, 'external');
      var modifier = parserModifier(parser);
      var getter =
          parserIs(parser, 'get') &&
          parser.tokens[parser.position + 1].kind == tokenIdentifier;
      var type = parserInferredType(memberToken);
      if (!getter) type = parserDeclarationType(parser, modifier);
      var member = parserName(parser);
      if (member == 'get' &&
          parser.tokens[parser.position].kind == tokenIdentifier) {
        getter = true;
        member = parserName(parser);
      }
      if (getter || parserIs(parser, '(')) {
        methods.add(
          parserFunction(parser, member, type, external, memberToken, getter),
        );
      } else {
        if (external) parserError(parser, 'external fields are not supported');
        var variables = parserVariablesRest(
          parser,
          type,
          member,
          modifier,
          memberToken,
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
  parserExpect(parser, '=');
  var result = parseAstType(parser);
  parserExpect(parser, 'Function');
  parserExpect(parser, '(');
  List<AstType> parameters = <AstType>[];
  while (!parserIs(parser, ')')) {
    parameters.add(parseAstType(parser));
    if (!parserTake(parser, ',')) break;
  }
  parserExpect(parser, ')');
  parserExpect(parser, ';');
  return AstTypedef(name, result, parameters, token);
}

AstDirective parserDirective(Parser parser, int kind, int token) {
  var uri = '';
  var prefix = '';
  var combinators = <AstCombinator>[];
  if (kind == astLibraryDirective) {
    if (!parserIs(parser, ';')) {
      uri = parserName(parser);
      while (parserTake(parser, '.')) uri = uri + '.' + parserName(parser);
    }
  } else {
    if (parser.tokens[parser.position].kind != tokenString) {
      parserError(parser, 'expected library URI');
    }
    uri = parser.tokens[parser.position].text;
    parser.position++;
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
  return AstDirective(kind, uri, prefix, token, combinators);
}

AstUnit parseUnit(Parser parser) {
  var unit = AstUnit(
    <AstDirective>[],
    <AstVariable>[],
    <AstFunction>[],
    <AstClass>[],
    <AstTypedef>[],
  );
  while (!parserIs(parser, '')) {
    var token = parser.position;
    if (parserTake(parser, 'import')) {
      unit.directives.add(parserDirective(parser, astImportDirective, token));
    } else if (parserTake(parser, 'export')) {
      unit.directives.add(parserDirective(parser, astExportDirective, token));
    } else if (parserTake(parser, 'library')) {
      unit.directives.add(parserDirective(parser, astLibraryDirective, token));
    } else if (parserTake(parser, 'class')) {
      unit.classes.add(parserClass(parser, token));
    } else if (parserTake(parser, 'typedef')) {
      unit.typedefs.add(parserTypedef(parser, token));
    } else {
      var external = parserTake(parser, 'external');
      var modifier = parserModifier(parser);
      var getter =
          parserIs(parser, 'get') &&
          parser.tokens[parser.position + 1].kind == tokenIdentifier;
      var type = parserInferredType(token);
      if (!getter) type = parserDeclarationType(parser, modifier);
      var name = parserName(parser);
      if (name == 'get' &&
          parser.tokens[parser.position].kind == tokenIdentifier) {
        getter = true;
        name = parserName(parser);
      }
      if (getter || parserIs(parser, '(')) {
        unit.functions.add(
          parserFunction(parser, name, type, external, token, getter),
        );
      } else {
        if (external)
          parserError(parser, 'external variables are not supported');
        var variables = parserVariablesRest(
          parser,
          type,
          name,
          modifier,
          token,
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
  return parserIs(parser, 'var') ||
      parserIs(parser, 'final') ||
      parserIs(parser, 'const') ||
      parserTypedDeclaration(parser);
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
  if (parserVariableStatement(parser)) {
    return AstStatement(
      astVariableStatement,
      <AstExpression>[],
      <AstStatement>[],
      parserVariables(parser),
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
    variables.add(
      parserVariableInitializer(
        parser,
        first.type,
        name,
        first.modifier,
        token,
      ),
    );
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
