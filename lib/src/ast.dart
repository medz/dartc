const int astInteger = 1;
const int astString = 2;
const int astBoolean = 3;
const int astNull = 4;
const int astName = 5;
const int astList = 6;
const int astMember = 7;
const int astCall = 8;
const int astUnary = 9;
const int astPostfix = 10;
const int astBinary = 11;
const int astAssignment = 12;
const int astConditional = 13;
const int astNamedArgument = 14;
const int astIndex = 15;
const int astInterpolation = 16;
const int astTypeTest = 17;
const int astTypeCast = 18;
const int astFunctionExpression = 19;
const int astCascade = 20;
const int astImplicitReceiver = 21;
const int astNullAware = 22;
const int astSpreadElement = 23;
const int astIfElement = 24;
const int astForElement = 25;
const int astNullAwareElement = 26;
const int astSwitchExpression = 27;
const int astIfCaseCondition = 28;

const int patternConstant = 1;
const int patternVariable = 2;
const int patternAnd = 3;
const int patternOr = 4;
const int patternRelational = 5;
const int patternCast = 6;
const int patternNullCheck = 7;
const int patternNullAssert = 8;
const int patternObject = 9;
const int patternList = 10;
const int patternRest = 11;

class AstPatternField {
  final String name;
  final int token;
  final AstPattern pattern;

  AstPatternField(this.name, this.token, this.pattern);
}

class AstPattern {
  final int kind;
  final int token;
  final String text;
  final List<AstPattern> children;
  List<AstPatternField> fields = const <AstPatternField>[];
  AstExpression? constant;
  bool constantContext = false;
  AstType? type;
  bool finalVariable = false;
  int binding = -1;

  AstPattern(this.kind, this.token, this.text, this.children);
}

class AstSwitchArm {
  final AstPattern pattern;
  final AstExpression? guard;
  final AstExpression value;

  AstSwitchArm(this.pattern, this.guard, this.value);
}

const String astCallIdentifier = 'identifier';
const String astCallSelector = 'selector';
const String astCallValue = 'value';
const String astCallNew = 'new';

class AstType {
  String name;
  List<AstType> arguments;
  int token;
  AstFunctionType? function;

  AstType(this.name, this.arguments, this.token);
}

class AstFunctionType {
  AstType result;
  List<AstParameter> parameters;

  AstFunctionType(this.result, this.parameters);
}

class AstExpression {
  AstFunction? function;
  AstStatement? loop;
  AstPattern? pattern;
  List<AstSwitchArm> arms = const <AstSwitchArm>[];
  int kind;
  String text;
  List<AstExpression> children;
  List<AstType> typeArguments;
  int token;
  int binding = -1;
  bool constant = false;

  AstExpression(
    this.kind,
    this.text,
    this.children,
    this.typeArguments,
    this.token,
  );
}

AstExpression astImplicitReceiverAccess(AstExpression expression) {
  while (expression.children[0].kind != astImplicitReceiver)
    expression = expression.children[0];
  return expression;
}

const int astEmptyStatement = 0;
const int astBlockStatement = 1;
const int astExpressionStatement = 2;
const int astVariableStatement = 3;
const int astReturnStatement = 4;
const int astIfStatement = 5;
const int astWhileStatement = 6;
const int astForStatement = 7;
const int astBreakStatement = 8;
const int astContinueStatement = 9;
const int astForInStatement = 10;
const int astDoWhileStatement = 11;
const int astSwitchStatement = 12;
const int astSwitchCaseStatement = 13;
const int astLabeledStatement = 14;
const int astLocalFunctionStatement = 15;

const int astImportDirective = 1;
const int astExportDirective = 2;
const int astLibraryDirective = 3;
const int astPartDirective = 4;
const int astPartOfUriDirective = 5;
const int astPartOfNameDirective = 6;

class AstVariable {
  List<AstExpression> metadata = const <AstExpression>[];
  AstType type;
  String name;
  List<AstExpression> initializer;
  String modifier;
  int token;
  int binding = -1;

  AstVariable(
    this.type,
    this.name,
    this.initializer,
    this.modifier,
    this.token,
  );
}

const int astRequiredPositional = 0;
const int astOptionalPositional = 1;
const int astNamedParameter = 2;

class AstParameter {
  List<AstExpression> metadata = const <AstExpression>[];
  AstType type;
  String name;
  bool fieldFormal;
  int token;
  int binding = -1;
  int kind = astRequiredPositional;
  bool required = false;
  AstExpression? defaultValue;

  AstParameter(this.type, this.name, this.fieldFormal, this.token);
}

class AstStatement {
  AstFunction? function;
  int kind;
  List<AstExpression> expressions;
  List<AstStatement> children;
  List<AstVariable> variables;
  List<AstExpression> condition;
  List<AstExpression> update;
  int token;

  AstStatement(
    this.kind,
    this.expressions,
    this.children,
    this.variables,
    this.condition,
    this.update,
    this.token,
  );
}

const int astFieldInitializer = 0;
const int astAssertInitializer = 1;
const int astSuperInitializer = 2;
const int astRedirectInitializer = 3;

class AstInitializer {
  int kind;
  String name;
  AstExpression expression;
  int token;
  AstExpression? message;

  AstInitializer(this.kind, this.name, this.expression, this.token);
}

class AstFunction {
  int local = -1;
  List<AstExpression> metadata = const <AstExpression>[];
  String name;
  AstType result;
  List<AstParameter> parameters;
  List<AstInitializer> initializers = const <AstInitializer>[];
  AstStatement? body;
  AstExpression? arrow;
  bool external;
  int token;
  bool getter;
  bool setter = false;
  bool constant = false;
  bool isStatic = false;

  AstFunction(
    this.name,
    this.result,
    this.parameters,
    this.body,
    this.arrow,
    this.external,
    this.token,
    this.getter,
  );
}

class AstClass {
  List<AstExpression> metadata = const <AstExpression>[];
  String name;
  List<AstVariable> fields;
  List<AstVariable> staticFields = const <AstVariable>[];
  List<AstFunction> constructors;
  List<AstFunction> methods;
  int token;

  AstClass(this.name, this.fields, this.constructors, this.methods, this.token);
}

class AstTypeParameter {
  List<AstExpression> metadata = const <AstExpression>[];
  String name;
  AstType? bound;
  int token;

  AstTypeParameter(this.name, this.bound, this.token);
}

class AstTypedef {
  List<AstExpression> metadata = const <AstExpression>[];
  List<AstTypeParameter> typeParameters = const <AstTypeParameter>[];
  String name;
  AstType type;
  int token;

  AstTypedef(this.name, this.type, this.token);
}

class AstCombinator {
  bool show;
  List<String> names;

  AstCombinator(this.show, this.names);
}

class AstConditionalUri {
  final String key;
  final String value;
  final String uri;
  final int token;

  AstConditionalUri(this.key, this.value, this.uri, this.token);
}

class AstDirective {
  List<AstConditionalUri> conditions = const <AstConditionalUri>[];
  List<AstExpression> metadata = const <AstExpression>[];
  int kind;
  String uri;
  String prefix;
  int token;
  List<AstCombinator> combinators;

  AstDirective(this.kind, this.uri, this.prefix, this.token, this.combinators);
}

class AstUnit {
  List<AstDirective> directives;
  List<AstVariable> variables;
  List<AstFunction> functions;
  List<AstClass> classes;
  List<AstTypedef> typedefs;

  AstUnit(
    this.directives,
    this.variables,
    this.functions,
    this.classes,
    this.typedefs,
  );
}
