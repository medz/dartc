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

Never _initError(SymbolTable symbols, int token, String message) {
  sourceError(symbols.program, symbols.program.tokens[token], message);
}

bool _requiresInitializer(SymbolTable symbols, AstVariable variable) {
  if (variable.modifier == 'final') return true;
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

List<ConstructorStep> planConstructorInitializers(
  SymbolTable symbols,
  AstClass owner,
  AstFunction syntax,
  ClassMembers members,
) {
  var initialized = List<int>.filled(owner.fields.length, 0);
  var steps = <ConstructorStep>[];
  var f = 0;
  while (f < owner.fields.length) {
    var field = owner.fields[f];
    if (syntax.constant && field.modifier != 'final')
      _initError(
        symbols,
        field.token,
        'const constructor requires final fields',
      );
    if (field.initializer.isNotEmpty) {
      initialized[f] = 1;
      steps.add(ConstructorStep(constructorDeclaration, f, f));
    }
    f++;
  }
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
  return steps;
}
