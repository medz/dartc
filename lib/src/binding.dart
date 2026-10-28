import 'ast.dart';
import 'source.dart';
import 'members.dart';

class LocalVariable {
  String name;
  int token;
  AstType type;
  int function = -1;
  int outer = -1;
  bool constant = false;
  bool finalVariable = false;
  bool lateVariable = false;
  AstFunction? lateInitializer;
  bool written = false;
  bool captured = false;
  bool writeCaptured = false;
  bool unavailable = false;

  LocalVariable(this.name, this.token, this.type);
}

class LocalFunctionBinding {
  final AstFunction syntax;
  FunctionBindings? body;

  LocalFunctionBinding(this.syntax);
}

class FunctionBindings {
  FunctionBindings? outer;
  List<int> captures = <int>[];
  List<LocalVariable> variables;
  int receiver;

  FunctionBindings(this.variables, this.receiver);

  FunctionBindings withReceiver(int receiver) {
    return FunctionBindings(variables, receiver)
      ..outer = outer
      ..captures = captures;
  }
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
  ClassMembers? members;
  final List<LocalVariable> guardVariables = <LocalVariable>[];
  int catchDepth = 0;

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
  if (token < variable.token)
    sourceError(
      binder.source,
      binder.source.tokens[token],
      'local referenced before declaration: ' + name,
    );
  return bindingCapture(binder, original);
}

LocalVariable bindingDeclaration(FunctionBindings bindings, int binding) {
  var variable = bindings.variables[binding];
  var outer = bindings.outer;
  while (variable.outer >= 0 && outer != null) {
    bindings = outer;
    variable = bindings.variables[variable.outer];
    outer = bindings.outer;
  }
  return variable;
}

int bindingCapture(LocalBinder binder, int original) {
  var outer = binder.outer!;
  var variable = outer.result.variables[original];
  if (!variable.constant) variable.captured = true;
  var i = 0;
  while (i < binder.result.variables.length) {
    if (binder.result.variables[i].outer == original) return i;
    i++;
  }
  var alias = LocalVariable(variable.name, variable.token, variable.type);
  alias.function = variable.function;
  alias.outer = original;
  alias.constant = variable.constant;
  alias.finalVariable = variable.finalVariable;
  alias.lateVariable = variable.lateVariable;
  var binding = binder.result.variables.length;
  binder.result.variables.add(alias);
  if (!variable.constant) binder.result.captures.add(binding);
  if (outer.result.receiver == original) binder.result.receiver = binding;
  return binding;
}

int bindingReceiver(LocalBinder binder, int scope) {
  var receiver = binder.result.receiver;
  if (receiver >= 0) {
    if (binder.result.variables[receiver].outer >= 0) return receiver;
    while (scope >= 0) {
      for (var variable in binder.scopes[scope].variables) {
        if (variable == receiver) return receiver;
      }
      scope = binder.scopes[scope].parent;
    }
    return -1;
  }
  var outer = binder.outer;
  if (outer == null) return -1;
  receiver = bindingReceiver(outer, binder.outerScope);
  if (receiver < 0) return -1;
  return bindingCapture(binder, receiver);
}

void bindingWrite(
  LocalBinder binder,
  int binding,
  int token, [
  bool patternAssignment = false,
]) {
  if (binding < 0) return;
  var bindings = binder.result;
  var variable = bindings.variables[binding];
  var declaration = bindingDeclaration(bindings, binding);
  LocalBinder? current = binder;
  // The SDK permits pattern assignments in guards; see specs/patterns.md.
  while (!patternAssignment && current != null) {
    for (var guarded in current.guardVariables) {
      if (identical(guarded, declaration))
        sourceError(
          binder.source,
          binder.source.tokens[token],
          'cannot assign a pattern variable in its guard',
        );
    }
    current = current.outer;
  }
  declaration.written = true;
  if (variable.outer < 0) return;
  while (true) {
    variable.writeCaptured = true;
    var outer = bindings.outer;
    if (outer == null || variable.outer < 0) return;
    bindings = outer;
    variable = bindings.variables[variable.outer];
  }
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

List<AstPattern> bindingPatternVariables(
  LocalBinder binder,
  AstPattern pattern,
) {
  if ((pattern.kind == patternVariable ||
          pattern.kind == patternAssignedVariable) &&
      pattern.text != '_')
    return <AstPattern>[pattern];
  var children = pattern.children;
  if (pattern.kind == patternObject)
    children = <AstPattern>[for (var field in pattern.fields) field.pattern];
  if (children.isEmpty) return <AstPattern>[];
  var variables = bindingPatternVariables(binder, children[0]);
  if (pattern.kind == patternOr) {
    var right = bindingPatternVariables(binder, children[1]);
    if (variables.length != right.length)
      sourceError(
        binder.source,
        binder.source.tokens[pattern.token],
        'logical-or patterns must bind the same variables',
      );
    for (var variable in right) {
      var found = false;
      for (var previous in variables) {
        if (previous.text == variable.text &&
            previous.finalVariable == variable.finalVariable)
          found = true;
      }
      if (!found)
        sourceError(
          binder.source,
          binder.source.tokens[variable.token],
          'logical-or variable name or finality differs',
        );
    }
  } else {
    for (var i = 1; i < children.length; i++) {
      for (var variable in bindingPatternVariables(binder, children[i])) {
        for (var previous in variables) {
          if (previous.text == variable.text)
            sourceError(
              binder.source,
              binder.source.tokens[variable.token],
              'duplicate pattern variable ' + variable.text,
            );
        }
        variables.add(variable);
      }
    }
  }
  return variables;
}

void bindingPattern(
  LocalBinder binder,
  int scope,
  AstPattern pattern, [
  bool irrefutable = false,
]) {
  if (irrefutable &&
      (pattern.kind == patternOr ||
          pattern.kind == patternRelational ||
          pattern.kind == patternNullCheck ||
          pattern.kind == patternConstant))
    sourceError(
      binder.source,
      binder.source.tokens[pattern.token],
      'refutable pattern in declaration or assignment',
    );
  if (pattern.kind == patternAssignedVariable) {
    pattern.binding = bindingReference(
      binder,
      scope,
      pattern.text,
      pattern.token,
    );
    if (pattern.binding < 0 ||
        binder.result.variables[pattern.binding].function >= 0)
      sourceError(
        binder.source,
        binder.source.tokens[pattern.token],
        'pattern assignment requires a local variable or parameter',
      );
    bindingWrite(binder, pattern.binding, pattern.token, true);
  }
  if (pattern.type case final type?) bindingType(binder, scope, type);
  if (pattern.kind == patternVariable && pattern.text != '_')
    pattern.binding = bindingLookup(binder, scope, pattern.text);
  if (pattern.constant case final constant?)
    bindingExpression(binder, scope, constant);
  for (var child in pattern.children)
    bindingPattern(binder, scope, child, irrefutable);
  for (var field in pattern.fields)
    bindingPattern(binder, scope, field.pattern, irrefutable);
}

void bindingPatternVersion(LocalBinder binder, int token) {
  if (!sourceVersionAtLeast(
    binder.source,
    binder.source.tokens[token].source,
    3,
    0,
  ))
    sourceError(
      binder.source,
      binder.source.tokens[token],
      'destructuring requires language version 3.0',
    );
}

void bindingPatternDeclarations(
  LocalBinder binder,
  int scope,
  AstPatternDeclaration declaration,
) {
  for (var variable in bindingPatternVariables(binder, declaration.pattern)) {
    var id = bindingDeclare(
      binder,
      scope,
      variable.text,
      variable.token,
      variable.type ?? AstType('', const <AstType>[], variable.token),
    );
    binder.result.variables[id].finalVariable = declaration.isFinal;
  }
}

void bindingPatternDeclaration(
  LocalBinder binder,
  int scope,
  AstPatternDeclaration declaration,
) {
  bindingPatternVersion(binder, declaration.pattern.token);
  bindingPattern(binder, scope, declaration.pattern, true);
  bindingExpressions(binder, scope, declaration.metadata);
}

int bindingPatternScope(
  LocalBinder binder,
  int scope,
  AstPattern pattern,
  bool readOnly,
) {
  var local = bindingScope(binder, scope);
  for (var variable in bindingPatternVariables(binder, pattern)) {
    var id = bindingDeclare(
      binder,
      local,
      variable.text,
      variable.token,
      variable.type ?? AstType('', const <AstType>[], variable.token),
    );
    binder.result.variables[id].finalVariable =
        readOnly || variable.finalVariable;
  }
  bindingPattern(binder, local, pattern);
  return local;
}

void bindingGuard(LocalBinder binder, int scope, AstExpression guard) {
  var variables = binder.scopes[scope].variables;
  for (var id in variables)
    binder.guardVariables.add(binder.result.variables[id]);
  bindingExpression(binder, scope, guard);
  for (var _ in variables) binder.guardVariables.removeLast();
}

int bindingIfCondition(LocalBinder binder, int scope, AstExpression condition) {
  if (condition.kind != astIfCaseCondition) {
    bindingExpression(binder, scope, condition);
    return scope;
  }
  if (!sourceVersionAtLeast(
    binder.source,
    binder.source.tokens[condition.token].source,
    3,
    0,
  ))
    sourceError(
      binder.source,
      binder.source.tokens[condition.token],
      'if-case requires language version 3.0',
    );
  bindingExpression(binder, scope, condition.children[0]);
  var local = bindingPatternScope(binder, scope, condition.pattern!, false);
  if (condition.children.length == 2)
    bindingGuard(binder, local, condition.children[1]);
  return local;
}

void bindingExpression(
  LocalBinder binder,
  int scope,
  AstExpression expression,
) {
  if (expression.kind == astPatternAssignment) {
    bindingPatternVersion(binder, expression.token);
    bindingPatternVariables(binder, expression.pattern!);
    bindingPattern(binder, scope, expression.pattern!, true);
    bindingExpression(binder, scope, expression.children[0]);
    return;
  }
  if (expression.kind == astSwitchExpression) {
    if (!sourceVersionAtLeast(
      binder.source,
      binder.source.tokens[expression.token].source,
      3,
      0,
    ))
      sourceError(
        binder.source,
        binder.source.tokens[expression.token],
        'switch expressions require language version 3.0',
      );
    bindingExpression(binder, scope, expression.children[0]);
    for (var arm in expression.arms) {
      var local = bindingPatternScope(binder, scope, arm.pattern, true);
      if (arm.guard case final guard?) bindingGuard(binder, local, guard);
      bindingExpression(binder, local, arm.value);
    }
    return;
  }
  if (expression.kind == astIfElement) {
    var local = bindingIfCondition(binder, scope, expression.children[0]);
    bindingExpression(binder, local, expression.children[1]);
    if (expression.children.length == 3)
      bindingExpression(binder, scope, expression.children[2]);
    return;
  }
  if (expression.kind == astForElement) {
    bindingStatement(binder, scope, expression.loop!);
    return;
  }
  if (expression.kind == astFunctionExpression) {
    var syntax = expression.function!;
    syntax.local = binder.functions.length;
    binder.functions.add(LocalFunctionBinding(syntax));
    bindingFunctionBody(binder, scope, syntax);
    return;
  }
  for (var type in expression.typeArguments) bindingType(binder, scope, type);
  if (expression.kind == astName) {
    expression.binding = expression.text == 'super'
        ? bindingReceiver(binder, scope)
        : bindingReference(binder, scope, expression.text, expression.token);
    var members = binder.members;
    if (expression.binding < 0 && members != null) {
      var member = lookupMember(
        members,
        expression.text,
        sourceLibrary(
          binder.source,
          binder.source.tokens[expression.token].source,
        ),
      );
      if (member >= 0 && !members.members[member].isStatic)
        bindingReceiver(binder, scope);
    }
  }
  var i = 0;
  while (i < expression.children.length) {
    bindingExpression(binder, scope, expression.children[i]);
    i++;
  }
  if (expression.kind == astAssignment ||
      (expression.kind == astUnary || expression.kind == astPostfix) &&
          (expression.text == '++' || expression.text == '--')) {
    var target = expression.children[0];
    if (target.kind == astName)
      bindingWrite(binder, target.binding, target.token);
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
    local.lateVariable = variable.lateVariable;
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
  if (statement.kind == astPatternDeclarationStatement) {
    bindingPatternDeclarations(binder, scope, statement.patternDeclaration!);
  } else if (statement.kind == astVariableStatement) {
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
    if (parameter.defaultValue case final value?)
      bindingExpression(binder, scope, value);
  }
  binder.functions[syntax.local].body = _bindFunctionLocals(
    binder.source,
    syntax,
    false,
    binder.functions,
    binder,
    scope,
    binder.members,
  );
}

FunctionBindings bindExpressionLocals(
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
  return binder.result;
}

void bindingStatement(LocalBinder binder, int scope, AstStatement statement) {
  var kind = statement.kind;
  if (kind == astRethrowStatement) {
    if (binder.catchDepth == 0)
      sourceError(
        binder.source,
        binder.source.tokens[statement.token],
        'rethrow requires an enclosing catch in the same function',
      );
    return;
  }
  if (kind == astTryStatement) {
    bindingStatement(binder, scope, statement.children[0]);
    for (var clause in statement.catches) {
      if (clause.type case final type?) bindingType(binder, scope, type);
      final local = bindingScope(binder, scope);
      for (var parameter in clause.parameters) {
        parameter.binding = bindingDeclare(
          binder,
          local,
          parameter.name,
          parameter.token,
          parameter.type,
        );
        binder.result.variables[parameter.binding].finalVariable = true;
      }
      binder.catchDepth++;
      bindingStatement(binder, local, clause.body);
      binder.catchDepth--;
    }
    if (statement.children.length == 2)
      bindingStatement(binder, scope, statement.children[1]);
    return;
  }
  if (kind == astPatternDeclarationStatement) {
    bindingPatternDeclaration(binder, scope, statement.patternDeclaration!);
    bindingExpressions(binder, scope, statement.expressions);
    return;
  }
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
  if (kind == astIfStatement) {
    var local = bindingIfCondition(binder, scope, statement.condition[0]);
    bindingBody(binder, local, statement.children[0]);
    if (statement.children.length == 2)
      bindingBody(binder, scope, statement.children[1]);
    return;
  }
  if (kind == astWhileStatement || kind == astDoWhileStatement) {
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
    if (statement.variables.isEmpty && statement.patternDeclaration == null)
      bindingWrite(
        binder,
        statement.expressions[1].binding,
        statement.expressions[1].token,
      );
    var loop = bindingScope(binder, scope);
    bindingDeclarations(binder, loop, statement.variables);
    if (statement.patternDeclaration case final declaration?) {
      bindingPatternDeclarations(binder, loop, declaration);
      bindingPatternDeclaration(binder, loop, declaration);
    }
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
    bindingCollectStatement(binder, loop, initial);
    bindingStatement(binder, loop, initial);
    bindingExpressions(binder, loop, statement.condition);
    bindingExpressions(binder, loop, statement.update);
    bindingBody(binder, loop, statement.children[1]);
    return;
  }
  if (kind == astSwitchStatement) {
    bindingSwitch(binder, scope, statement);
    return;
  }

  var i = 0;
  while (i < statement.variables.length) {
    bindingType(binder, scope, statement.variables[i].type);
    bindingExpressions(binder, scope, statement.variables[i].metadata);
    final variable = statement.variables[i];
    if (variable.lateVariable && variable.initializer.isNotEmpty) {
      final syntax = AstFunction(
        '',
        AstType('', const <AstType>[], variable.token),
        const <AstParameter>[],
        null,
        variable.initializer[0],
        false,
        variable.token,
        false,
      );
      syntax.local = binder.functions.length;
      binder.functions.add(LocalFunctionBinding(syntax));
      variable.lateInitializer = syntax;
      binder.result.variables[variable.binding].lateInitializer = syntax;
      bindingFunctionBody(binder, scope, syntax);
    } else {
      bindingExpressions(binder, scope, variable.initializer);
    }
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

void bindingSwitch(LocalBinder binder, int scope, AstStatement statement) {
  bindingExpressions(binder, scope, statement.expressions);
  var cases = statement.cases;
  var start = 0;
  while (start < cases.length) {
    var end = cases[start].bodyIndex;
    var bodyScope = -1;
    var shared = start != end;
    for (var i = start; i <= end; i++) {
      var branch = cases[i];
      var local = scope;
      if (branch.pattern case final pattern?) {
        local = bindingPatternScope(binder, scope, pattern, false);
        branch.bindings = binder.scopes[local].variables;
        if (branch.guard case final guard?) bindingGuard(binder, local, guard);
      }
      if (branch.labels.isNotEmpty) shared = true;
      bodyScope = local;
    }
    if (shared) {
      bodyScope = bindingScope(binder, scope);
      for (var i = start; i <= end; i++) {
        for (var id in cases[i].bindings) {
          var variable = binder.result.variables[id];
          var found = false;
          for (var previous in binder.scopes[bodyScope].variables)
            if (binder.result.variables[previous].name == variable.name)
              found = true;
          if (!found) {
            var joined = bindingDeclare(
              binder,
              bodyScope,
              variable.name,
              variable.token,
              AstType('', const <AstType>[], variable.token),
            );
            binder.result.variables[joined].finalVariable =
                variable.finalVariable;
          }
        }
      }
      var joined = binder.scopes[bodyScope].variables;
      cases[end].sharedBindings = joined;
      for (var i = start; i <= end; i++) {
        var sources = <int>[];
        for (var id in joined) {
          var source = -1;
          for (var candidate in cases[i].bindings)
            if (binder.result.variables[candidate].name ==
                binder.result.variables[id].name)
              source = candidate;
          sources.add(source);
        }
        cases[i].sharedSources = sources;
      }
    }
    bindingStatements(binder, bindingScope(binder, bodyScope), cases[end].body);
    start = end + 1;
  }
}

FunctionBindings bindFunctionLocals(
  SourceProgram source,
  AstFunction syntax,
  bool receiver, [
  List<LocalFunctionBinding>? functions,
  ClassMembers? members,
]) {
  return _bindFunctionLocals(
    source,
    syntax,
    receiver,
    functions ?? <LocalFunctionBinding>[],
    null,
    -1,
    members,
  );
}

FunctionBindings _bindFunctionLocals(
  SourceProgram source,
  AstFunction syntax,
  bool receiver,
  List<LocalFunctionBinding> functions,
  LocalBinder? outer,
  int outerScope,
  ClassMembers? members,
) {
  var result = FunctionBindings(<LocalVariable>[], -1)..outer = outer?.result;
  var binder = LocalBinder(source, result, <BindingScope>[], functions);
  binder.outer = outer;
  binder.outerScope = outerScope;
  binder.members = members;
  binder.wildcards = sourceVersionAtLeast(
    source,
    source.tokens[syntax.token].source,
    3,
    7,
  );
  var parameters = bindingScope(binder, -1);
  var initializers = -1;
  if (syntax.initializers.isNotEmpty) initializers = bindingScope(binder, -1);
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
    if (!parameter.fieldFormal || initializers >= 0) {
      parameter.binding = result.variables.length;
      var variable = LocalVariable(
        parameter.name,
        parameter.token,
        parameter.type,
      );
      variable.finalVariable = parameter.fieldFormal;
      result.variables.add(variable);
      if (!parameter.fieldFormal)
        binder.scopes[parameters].variables.add(parameter.binding);
      if (initializers >= 0)
        binder.scopes[initializers].variables.add(parameter.binding);
    }
    i++;
  }
  i = 0;
  while (i < syntax.initializers.length) {
    var initializer = syntax.initializers[i];
    bindingExpression(binder, initializers, initializer.expression);
    if (initializer.message case final message?)
      bindingExpression(binder, initializers, message);
    i++;
  }
  if (syntax.body case final body?) bindingStatement(binder, parameters, body);
  if (syntax.arrow case final arrow?)
    bindingExpression(binder, parameters, arrow);
  return result;
}

void collectWrittenBinding(int binding, List<bool> seen, List<int> written) {
  if (binding >= 0 && !seen[binding]) {
    seen[binding] = true;
    written.add(binding);
  }
}

void collectWrittenPattern(
  AstPattern pattern,
  List<bool> seen,
  List<int> written,
) {
  collectWrittenBinding(pattern.binding, seen, written);
  for (var child in pattern.children)
    collectWrittenPattern(child, seen, written);
  for (var field in pattern.fields)
    collectWrittenPattern(field.pattern, seen, written);
}

void collectWrittenExpression(
  AstExpression expression,
  List<bool> seen,
  List<int> written,
) {
  switch (expression.kind) {
    case astPatternAssignment:
      collectWrittenPattern(expression.pattern!, seen, written);
    case astSwitchExpression:
      for (var arm in expression.arms) {
        if (arm.guard case final guard?)
          collectWrittenExpression(guard, seen, written);
        collectWrittenExpression(arm.value, seen, written);
      }
    case astForElement:
      collectWrittenStatement(expression.loop!, seen, written);
      return;
    case astAssignment:
    case astUnary || astPostfix
        when expression.text == '++' || expression.text == '--':
      var target = expression.children[0];
      if (target.kind == astName)
        collectWrittenBinding(target.binding, seen, written);
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
  for (var clause in statement.catches)
    collectWrittenStatement(clause.body, seen, written);
  for (var branch in statement.cases) {
    if (branch.pattern case final pattern?)
      collectWrittenPattern(pattern, seen, written);
    if (branch.guard case final guard?)
      collectWrittenExpression(guard, seen, written);
    for (var child in branch.body)
      collectWrittenStatement(child, seen, written);
  }
  if (statement.patternDeclaration case final declaration?)
    collectWrittenPattern(declaration.pattern, seen, written);
  if (statement.kind == astForInStatement &&
      statement.variables.isEmpty &&
      statement.patternDeclaration == null)
    collectWrittenBinding(statement.expressions[1].binding, seen, written);
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
    while (!variable.lateVariable && value < variable.initializer.length) {
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
