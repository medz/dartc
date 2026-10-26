import 'ast.dart';
import 'source.dart';

class LocalVariable {
  String name;
  int token;
  AstType type;

  LocalVariable(this.name, this.token, this.type);
}

class FunctionBindings {
  List<LocalVariable> variables;
  int receiver;

  FunctionBindings(this.variables, this.receiver);
}

class BindingScope {
  int parent;
  List<int> variables;

  BindingScope(this.parent, this.variables);
}

class LocalBinder {
  SourceProgram source;
  FunctionBindings result;
  List<BindingScope> scopes;

  LocalBinder(this.source, this.result, this.scopes);
}

int bindingScope(LocalBinder binder, int parent) {
  var id = binder.scopes.length;
  binder.scopes.add(BindingScope(parent, <int>[]));
  return id;
}

int bindingDeclare(
  LocalBinder binder,
  int scope,
  String name,
  int token,
  AstType type,
) {
  var variables = binder.scopes[scope].variables;
  var i = 0;
  while (i < variables.length) {
    if (name != '_' && binder.result.variables[variables[i]].name == name) {
      sourceError(
        binder.source,
        binder.source.tokens[token],
        'duplicate local declaration ' + name,
      );
    }
    i++;
  }
  var id = binder.result.variables.length;
  binder.result.variables.add(LocalVariable(name, token, type));
  variables.add(id);
  return id;
}

int bindingLookup(LocalBinder binder, int scope, String name) {
  if (name == '_') return -1;
  while (scope >= 0) {
    var variables = binder.scopes[scope].variables;
    var i = 0;
    while (i < variables.length) {
      var id = variables[i];
      if (binder.result.variables[id].name == name) return id;
      i++;
    }
    scope = binder.scopes[scope].parent;
  }
  return -1;
}

void bindingExpression(
  LocalBinder binder,
  int scope,
  AstExpression expression,
) {
  if (expression.kind == astName) {
    expression.binding = bindingLookup(binder, scope, expression.text);
  }
  var i = 0;
  while (i < expression.children.length) {
    bindingExpression(binder, scope, expression.children[i]);
    i++;
  }
}

void bindingExpressions(
  LocalBinder binder,
  int scope,
  List<AstExpression> expressions,
) {
  var i = 0;
  while (i < expressions.length) {
    bindingExpression(binder, scope, expressions[i]);
    i++;
  }
}

void bindingDeclarations(
  LocalBinder binder,
  int scope,
  List<AstVariable> variables,
) {
  var i = 0;
  while (i < variables.length) {
    var variable = variables[i];
    variable.binding = bindingDeclare(
      binder,
      scope,
      variable.name,
      variable.token,
      variable.type,
    );
    i++;
  }
}

void bindingCollectStatement(
  LocalBinder binder,
  int scope,
  AstStatement statement,
) {
  while (statement.kind == astLabeledStatement) {
    statement = statement.children[0];
  }
  if (statement.kind == astVariableStatement) {
    bindingDeclarations(binder, scope, statement.variables);
  }
}

void bindingCollect(
  LocalBinder binder,
  int scope,
  List<AstStatement> statements,
) {
  var i = 0;
  while (i < statements.length) {
    bindingCollectStatement(binder, scope, statements[i]);
    i++;
  }
}

void bindingStatements(
  LocalBinder binder,
  int scope,
  List<AstStatement> statements,
) {
  bindingCollect(binder, scope, statements);
  var i = 0;
  while (i < statements.length) {
    bindingStatement(binder, scope, statements[i]);
    i++;
  }
}

void bindingBody(LocalBinder binder, int scope, AstStatement statement) {
  if (statement.kind == astBlockStatement) {
    bindingStatement(binder, scope, statement);
    return;
  }
  var body = bindingScope(binder, scope);
  bindingCollectStatement(binder, body, statement);
  bindingStatement(binder, body, statement);
}

void bindingStatement(LocalBinder binder, int scope, AstStatement statement) {
  var kind = statement.kind;
  if (kind == astBreakStatement || kind == astContinueStatement) return;
  if (kind == astLabeledStatement) {
    bindingStatement(binder, scope, statement.children[0]);
    return;
  }
  if (kind == astBlockStatement) {
    bindingStatements(binder, bindingScope(binder, scope), statement.children);
    return;
  }
  if (kind == astIfStatement ||
      kind == astWhileStatement ||
      kind == astDoWhileStatement) {
    bindingExpressions(binder, scope, statement.condition);
    var i = 0;
    while (i < statement.children.length) {
      bindingBody(binder, scope, statement.children[i]);
      i++;
    }
    return;
  }
  if (kind == astForInStatement) {
    bindingExpressions(binder, scope, statement.expressions);
    var loop = bindingScope(binder, scope);
    bindingDeclarations(binder, loop, statement.variables);
    bindingBody(binder, loop, statement.children[0]);
    return;
  }
  if (kind == astForStatement) {
    var loop = bindingScope(binder, scope);
    var initial = statement.children[0];
    bindingDeclarations(binder, loop, initial.variables);
    bindingStatement(binder, loop, initial);
    bindingExpressions(binder, loop, statement.condition);
    bindingExpressions(binder, loop, statement.update);
    bindingBody(binder, loop, statement.children[1]);
    return;
  }
  if (kind == astSwitchStatement) {
    bindingExpressions(binder, scope, statement.expressions);
    var i = 0;
    while (i < statement.children.length) {
      var branch = statement.children[i];
      bindingExpressions(binder, scope, branch.expressions);
      bindingStatements(binder, bindingScope(binder, scope), branch.children);
      i++;
    }
    return;
  }
  var i = 0;
  while (i < statement.variables.length) {
    bindingExpressions(binder, scope, statement.variables[i].initializer);
    i++;
  }
  bindingExpressions(binder, scope, statement.expressions);
  bindingExpressions(binder, scope, statement.condition);
  bindingExpressions(binder, scope, statement.update);
  i = 0;
  while (i < statement.children.length) {
    bindingStatement(binder, scope, statement.children[i]);
    i++;
  }
}

FunctionBindings bindFunctionLocals(
  SourceProgram source,
  AstFunction syntax,
  bool receiver,
) {
  var result = FunctionBindings(<LocalVariable>[], -1);
  var binder = LocalBinder(source, result, <BindingScope>[]);
  var parameters = bindingScope(binder, -1);
  if (receiver) {
    result.receiver = bindingDeclare(
      binder,
      parameters,
      'this',
      syntax.token,
      AstType('', <AstType>[], syntax.token),
    );
  }
  var i = 0;
  while (i < syntax.parameters.length) {
    var parameter = syntax.parameters[i];
    var previous = 0;
    while (previous < i) {
      if (parameter.name != '_' &&
          syntax.parameters[previous].name == parameter.name) {
        sourceError(
          source,
          source.tokens[parameter.token],
          'duplicate parameter ' + parameter.name,
        );
      }
      previous++;
    }
    parameter.binding = -1;
    if (!parameter.fieldFormal) {
      parameter.binding = result.variables.length;
      result.variables.add(
        LocalVariable(parameter.name, parameter.token, parameter.type),
      );
      binder.scopes[parameters].variables.add(parameter.binding);
    }
    i++;
  }
  bindingStatements(binder, parameters, syntax.body);
  bindingExpressions(binder, parameters, syntax.arrow);
  return result;
}
