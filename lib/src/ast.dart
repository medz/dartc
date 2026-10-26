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

class AstType {
  String name;
  List<AstType> arguments;
  int token;

  AstType(this.name, this.arguments, this.token);
}

class AstExpression {
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

const int astImportDirective = 1;
const int astExportDirective = 2;
const int astLibraryDirective = 3;

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

class AstFunction {
  List<AstExpression> metadata = const <AstExpression>[];
  String name;
  AstType result;
  List<AstParameter> parameters;
  List<AstStatement> body;
  List<AstExpression> arrow;
  bool external;
  int token;
  bool getter;
  bool setter = false;
  bool constant = false;

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
  List<AstFunction> constructors;
  List<AstFunction> methods;
  int token;

  AstClass(this.name, this.fields, this.constructors, this.methods, this.token);
}

class AstTypedef {
  List<AstExpression> metadata = const <AstExpression>[];
  String name;
  AstType result;
  List<AstType> parameterTypes;
  int token;

  AstTypedef(this.name, this.result, this.parameterTypes, this.token);
}

class AstCombinator {
  bool show;
  List<String> names;

  AstCombinator(this.show, this.names);
}

class AstDirective {
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
