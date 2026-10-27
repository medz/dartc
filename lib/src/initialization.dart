import 'ast.dart';
import 'members.dart';
import 'resolve_type.dart';
import 'source.dart';
import 'symbols.dart';
import 'types.dart';

const int constructorDeclaration = 0;
const int constructorFormal = 1;
const int constructorExplicit = 2;

class ConstructorStep {
  final int kind;
  final int index;
  final int field;

  const ConstructorStep(this.kind, this.index, this.field);
}

class ConstructorPlan {
  final List<ConstructorStep> steps;
  final int redirectTarget;

  const ConstructorPlan(this.steps, this.redirectTarget);
}

Never _initError(SymbolTable symbols, int token, String message) {
  sourceError(symbols.program, symbols.program.tokens[token], message);
}

bool _requiresInitializer(SymbolTable symbols, AstVariable variable) {
  if (variable.modifier == 'final' || variable.modifier == 'const') return true;
  return variable.type.name != '' &&
      !typeCanBeNull(resolveType(symbols, variable.type));
}

void checkInitializers(SymbolTable symbols, AstUnit unit) {
  var i = 0;
  while (i < unit.variables.length) {
    var variable = unit.variables[i];
    if (variable.initializer.isEmpty &&
        _requiresInitializer(symbols, variable)) {
      _initError(symbols, variable.token, 'missing initializer');
    }
    i++;
  }
  i = 0;
  while (i < unit.classes.length) {
    var owner = unit.classes[i];
    var f = 0;
    while (f < owner.fields.length) {
      var field = owner.fields[f];
      if (field.modifier == 'const') {
        _initError(symbols, field.token, 'const instance field');
      }
      f++;
    }
    f = 0;
    while (f < owner.staticFields.length) {
      var field = owner.staticFields[f];
      if (field.initializer.isEmpty && _requiresInitializer(symbols, field)) {
        _initError(symbols, field.token, 'missing static initializer');
      }
      f++;
    }
    i++;
  }
}

int _initializerField(
  SymbolTable symbols,
  ClassMembers members,
  String name,
  int token,
) {
  var member = lookupMember(members, name);
  if (member < 0 || members.members[member].field < 0)
    _initError(symbols, token, 'initializer requires an own instance field');
  return members.members[member].field;
}

ConstructorPlan planConstructorInitializers(
  SymbolTable symbols,
  AstClass owner,
  AstFunction syntax,
  ClassMembers members,
  List<int> classFunctions,
) {
  var redirectTarget = -1;
  if (syntax.initializers.isNotEmpty &&
      syntax.initializers[0].kind == astRedirectInitializer) {
    var initializer = syntax.initializers[0];
    if (syntax.initializers.length != 1)
      _initError(
        symbols,
        initializer.token,
        'redirect cannot have other initializers',
      );
    if (syntax.body != null || syntax.arrow != null)
      _initError(
        symbols,
        syntax.token,
        'redirecting constructor cannot have a body',
      );
    var parameter = 0;
    while (parameter < syntax.parameters.length) {
      var formal = syntax.parameters[parameter];
      if (formal.fieldFormal)
        _initError(
          symbols,
          formal.token,
          'redirecting constructor cannot have field formals',
        );
      parameter++;
    }
    var call = initializer.expression;
    var callee = call.children[0];
    if (call.typeArguments.isNotEmpty ||
        callee.typeArguments.isNotEmpty ||
        callee.kind == astMember && callee.children[0].typeArguments.isNotEmpty)
      _initError(
        symbols,
        call.token,
        'nongeneric constructor does not accept type arguments',
      );
    var name = '';
    if (callee.kind == astMember)
      name = constructorSelector(symbols.program, callee.text, callee.token);
    var ordinal = lookupConstructor(members, name);
    if (ordinal < 0)
      _initError(
        symbols,
        callee.token,
        'unknown redirecting constructor target',
      );
    redirectTarget = classFunctions[ordinal];
  }
  var initialized = const <int>[];
  var steps = const <ConstructorStep>[];
  if (redirectTarget < 0) {
    initialized = List<int>.filled(owner.fields.length, 0);
    steps = <ConstructorStep>[];
  }
  var f = 0;
  while (f < owner.fields.length) {
    var field = owner.fields[f];
    if (syntax.constant && field.modifier != 'final')
      _initError(
        symbols,
        field.token,
        'const constructor requires final fields',
      );
    if (redirectTarget < 0 && field.initializer.isNotEmpty) {
      initialized[f] = 1;
      steps.add(ConstructorStep(constructorDeclaration, f, f));
    }
    f++;
  }
  if (redirectTarget >= 0)
    return ConstructorPlan(const <ConstructorStep>[], redirectTarget);
  var p = 0;
  while (p < syntax.parameters.length) {
    var parameter = syntax.parameters[p];
    if (parameter.fieldFormal) {
      var field = _initializerField(
        symbols,
        members,
        parameter.name,
        parameter.token,
      );
      if ((initialized[field] & 2) != 0 ||
          initialized[field] != 0 && owner.fields[field].modifier == 'final')
        _initError(symbols, parameter.token, 'field initialized twice');
      initialized[field] |= 2;
      steps.add(ConstructorStep(constructorFormal, p, field));
    }
    p++;
  }
  var i = 0;
  while (i < syntax.initializers.length) {
    var initializer = syntax.initializers[i];
    if (initializer.kind != astFieldInitializer)
      _initError(
        symbols,
        initializer.token,
        'unsupported constructor initializer',
      );
    var field = _initializerField(
      symbols,
      members,
      initializer.name,
      initializer.token,
    );
    if ((initialized[field] & 6) != 0 ||
        initialized[field] != 0 && owner.fields[field].modifier == 'final')
      _initError(symbols, initializer.token, 'field initialized twice');
    initialized[field] |= 4;
    steps.add(ConstructorStep(constructorExplicit, i, field));
    i++;
  }
  f = 0;
  while (f < owner.fields.length) {
    if (initialized[f] == 0 && _requiresInitializer(symbols, owner.fields[f]))
      _initError(symbols, owner.fields[f].token, 'missing field initializer');
    f++;
  }
  return ConstructorPlan(steps, -1);
}

void checkConstructorRedirects(
  SymbolTable symbols,
  List<AstFunction> syntax,
  List<ConstructorPlan> plans,
) {
  var states = List<int>.filled(plans.length, 0);
  var function = 0;
  while (function < plans.length) {
    var current = function;
    while (current >= 0 && states[current] == 0) {
      states[current] = 1;
      current = plans[current].redirectTarget;
    }
    if (current >= 0 && states[current] == 1)
      _initError(
        symbols,
        syntax[current].initializers[0].token,
        'redirecting constructors cannot be cyclic',
      );
    current = function;
    while (current >= 0 && states[current] == 1) {
      states[current] = 2;
      current = plans[current].redirectTarget;
    }
    function++;
  }
}
