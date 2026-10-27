import 'ast.dart';
import 'source.dart';

class LocalVariable {
  String name;
  int token;
  AstType type;
  int function = -1;
  int outer = -1;
  bool constant = false;
  bool finalVariable = false;

  LocalVariable(this.name, this.token, this.type);
}

class LocalFunctionBinding {
  final AstFunction syntax;
  FunctionBindings? body;

  LocalFunctionBinding(this.syntax);
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
  bool wildcards = true;
  final List<LocalFunctionBinding> functions;
  LocalBinder? outer;
  int outerScope = -1;

  LocalBinder(this.source, this.result, this.scopes, this.functions);
}

void bindFunctionTypeParameters(SourceProgram source, AstFunctionType syntax) {
  var i = 0;
  while (i < syntax.parameters.length) {
    var parameter = syntax.parameters[i];
    var wildcard =
        parameter.kind != astNamedParameter &&
        parameter.name == '_' &&
        sourceVersionAtLeast(
          source,
          source.tokens[parameter.token].source,
          3,
          7,
        );
    if (parameter.name != '' && !wildcard) {
      var previous = 0;
      while (previous < i) {
        if (syntax.parameters[previous].name == parameter.name) {
          sourceError(
            source,
            source.tokens[parameter.token],
            'duplicate function type parameter ' + parameter.name,
          );
        }
        previous++;
      }
    }
    i++;
  }
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
    if ((!binder.wildcards || name != '_') &&
        binder.result.variables[variables[i]].name == name) {
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
  if (binder.wildcards && name == '_') return -1;
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

int bindingReference(LocalBinder binder, int scope, String name, int token) {
  var binding = bindingLookup(binder, scope, name);
  if (binding >= 0) {
    var variable = binder.result.variables[binding];
    if (variable.function >= 0 &&
        token < binder.functions[variable.function].syntax.token)
      sourceError(
        binder.source,
        binder.source.tokens[token],
        'local function referenced before declaration: ' + name,
      );
    return binding;
  }
  var outer = binder.outer;
  if (outer == null) return -1;
  var original = bindingReference(outer, binder.outerScope, name, token);
  if (original < 0) return -1;
  var variable = outer.result.variables[original];
  if (variable.function < 0 && !variable.constant)
    sourceError(
      binder.source,
      binder.source.tokens[token],
      'capturing outer local is not supported: ' + name,
    );
  if (token < variable.token)
    sourceError(
      binder.source,
      binder.source.tokens[token],
      'local referenced before declaration: ' + name,
    );
  var i = 0;
  while (i < binder.result.variables.length) {
    if (binder.result.variables[i].outer == original) return i;
    i++;
  }
  var alias = LocalVariable(name, variable.token, variable.type);
  alias.function = variable.function;
  alias.outer = original;
  alias.constant = variable.constant;
  alias.finalVariable = true;
  binder.result.variables.add(alias);
  return binder.result.variables.length - 1;
}

void bindingType(LocalBinder binder, int scope, AstType syntax) {
  var function = syntax.function;
  if (function != null) {
    bindingType(binder, scope, function.result);
    for (var parameter in function.parameters)
      bindingType(binder, scope, parameter.type);
  } else {
    var name = syntax.name;
    if (name.endsWith('?')) name = name.substring(0, name.length - 1);
    var dot = name.indexOf('.');
    if (dot >= 0) name = name.substring(0, dot);
    if (name != '' && name != 'void' && name != 'dynamic') {
      LocalBinder? current = binder;
      var at = scope;
      while (current != null) {
        if (bindingLookup(current, at, name) >= 0)
          sourceError(
            binder.source,
            binder.source.tokens[syntax.token],
            'local declaration is not a type: ' + name,
          );
        at = current.outerScope;
        current = current.outer;
      }
    }
  }
  for (var argument in syntax.arguments) bindingType(binder, scope, argument);
}

void bindingExpression(
  LocalBinder binder,
  int scope,
  AstExpression expression,
) {
  if (expression.kind == astFunctionExpression) {
    var syntax = expression.function!;
    syntax.local = binder.functions.length;
    binder.functions.add(LocalFunctionBinding(syntax));
    bindingFunctionBody(binder, scope, syntax);
    return;
  }
  for (var type in expression.typeArguments) bindingType(binder, scope, type);
  if (expression.kind == astName) {
    expression.binding = bindingReference(
      binder,
      scope,
      expression.text,
      expression.token,
    );
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
    var local = binder.result.variables[variable.binding];
    local.constant = variable.modifier == 'const';
    local.finalVariable = local.constant || variable.modifier == 'final';
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
  } else if (statement.kind == astLocalFunctionStatement) {
    var syntax = statement.function!;
    syntax.local = binder.functions.length;
    binder.functions.add(LocalFunctionBinding(syntax));
    var id = bindingDeclare(
      binder,
      scope,
      syntax.name,
      syntax.token,
      AstType('', <AstType>[], syntax.token),
    );
    binder.result.variables[id].function = syntax.local;
    binder.result.variables[id].finalVariable = true;
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

void bindingFunctionBody(LocalBinder binder, int scope, AstFunction syntax) {
  bindingType(binder, scope, syntax.result);
  bindingExpressions(binder, scope, syntax.metadata);
  for (var parameter in syntax.parameters) {
    bindingType(binder, scope, parameter.type);
    bindingExpressions(binder, scope, parameter.metadata);
    var value = parameter.defaultValue;
    if (value != null) bindingExpression(binder, scope, value);
  }
  binder.functions[syntax.local].body = _bindFunctionLocals(
    binder.source,
    syntax,
    false,
    binder.functions,
    binder,
    scope,
  );
}

void bindExpressionFunctions(
  SourceProgram source,
  AstExpression expression,
  List<LocalFunctionBinding> functions,
) {
  var binder = LocalBinder(
    source,
    FunctionBindings(<LocalVariable>[], -1),
    <BindingScope>[],
    functions,
  );
  bindingExpression(binder, -1, expression);
}

void bindingStatement(LocalBinder binder, int scope, AstStatement statement) {
  var kind = statement.kind;
  if (kind == astLocalFunctionStatement) {
    bindingFunctionBody(binder, scope, statement.function!);
    return;
  }
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
    var variable = 0;
    while (variable < statement.variables.length) {
      bindingType(binder, loop, statement.variables[variable].type);
      bindingExpressions(binder, loop, statement.variables[variable].metadata);
      variable++;
    }
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
    bindingType(binder, scope, statement.variables[i].type);
    bindingExpressions(binder, scope, statement.variables[i].metadata);
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
  bool receiver, [
  List<LocalFunctionBinding>? functions,
]) {
  return _bindFunctionLocals(
    source,
    syntax,
    receiver,
    functions ?? <LocalFunctionBinding>[],
    null,
    -1,
  );
}

FunctionBindings _bindFunctionLocals(
  SourceProgram source,
  AstFunction syntax,
  bool receiver,
  List<LocalFunctionBinding> functions,
  LocalBinder? outer,
  int outerScope,
) {
  var result = FunctionBindings(<LocalVariable>[], -1);
  var binder = LocalBinder(source, result, <BindingScope>[], functions);
  binder.outer = outer;
  binder.outerScope = outerScope;
  binder.wildcards = sourceVersionAtLeast(
    source,
    source.tokens[syntax.token].source,
    3,
    7,
  );
  var parameters = bindingScope(binder, -1);
  if (receiver) {
    result.receiver = bindingDeclare(
      binder,
      parameters,
      'this',
      syntax.token,
      AstType('', <AstType>[], syntax.token),
    );
    result.variables[result.receiver].finalVariable = true;
  }
  var i = 0;
  while (i < syntax.parameters.length) {
    var parameter = syntax.parameters[i];
    var previous = 0;
    while (previous < i) {
      if ((!binder.wildcards || parameter.name != '_') &&
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

void collectWrittenBinding(int binding, List<bool> seen, List<int> written) {
  if (binding >= 0 && !seen[binding]) {
    seen[binding] = true;
    written.add(binding);
  }
}

void collectWrittenExpression(
  AstExpression expression,
  List<bool> seen,
  List<int> written,
) {
  if (expression.kind == astAssignment ||
      (expression.kind == astUnary || expression.kind == astPostfix) &&
          (expression.text == '++' || expression.text == '--')) {
    var target = expression.children[0];
    if (target.kind == astName) {
      collectWrittenBinding(target.binding, seen, written);
    }
  }
  var i = 0;
  while (i < expression.children.length) {
    collectWrittenExpression(expression.children[i], seen, written);
    i++;
  }
}

void collectWrittenStatement(
  AstStatement statement,
  List<bool> seen,
  List<int> written,
) {
  var i = 0;
  while (i < statement.expressions.length) {
    collectWrittenExpression(statement.expressions[i], seen, written);
    i++;
  }
  i = 0;
  while (i < statement.condition.length) {
    collectWrittenExpression(statement.condition[i], seen, written);
    i++;
  }
  i = 0;
  while (i < statement.update.length) {
    collectWrittenExpression(statement.update[i], seen, written);
    i++;
  }
  i = 0;
  while (i < statement.variables.length) {
    var variable = statement.variables[i];
    collectWrittenBinding(variable.binding, seen, written);
    var value = 0;
    while (value < variable.initializer.length) {
      collectWrittenExpression(variable.initializer[value], seen, written);
      value++;
    }
    i++;
  }
  i = 0;
  while (i < statement.children.length) {
    collectWrittenStatement(statement.children[i], seen, written);
    i++;
  }
}
