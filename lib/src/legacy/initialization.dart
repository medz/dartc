import 'ast.dart';
import 'frontend/parameters.dart';
import 'ir.dart';
import 'members.dart';
import 'resolve_type.dart';
import 'source.dart';
import 'symbols.dart';
import 'types.dart';

const int constructorDeclaration = 0;
const int constructorFormal = 1;
const int constructorExplicit = 2;

class const ConstructorStep(final int kind, final int index, final int field);

class const ConstructorPlan(
  final List<ConstructorStep> steps,
  final int redirectTarget, [
  final int superTarget = -1,
  final AstExpression? superCall,
  final List<int> superParameters = const <int>[],
]);

Never _initError(SymbolTable symbols, int token, String message) {
  sourceError(symbols.program, symbols.program.tokens[token], message);
}

bool _requiresInitializer(
  SymbolTable symbols,
  AstVariable variable, [
  int type = -1,
]) {
  if (variable.lateVariable) return false;
  if (variable.modifier == 'final' || variable.modifier == 'const') return true;
  if (type < 0 && variable.type.name == '') return false;
  return !typeIsSubtype(
    tNull,
    type < 0 ? resolveType(symbols, variable.type) : type,
  );
}

void checkInitializers(
  SymbolTable symbols,
  AstUnit unit,
  List<int> fieldStarts,
  List<int> fieldTypes,
) {
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
    var hasGenerative = owner.constructors.isEmpty;
    for (final constructor in owner.constructors)
      if (!constructor.factory) hasGenerative = true;
    var f = 0;
    while (f < owner.fields.length) {
      var field = owner.fields[f];
      if (!hasGenerative &&
          field.initializer.isEmpty &&
          _requiresInitializer(symbols, field, fieldTypes[fieldStarts[i] + f]))
        _initError(
          symbols,
          field.token,
          'field requires an initializer without a generative constructor',
        );
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

void checkConstructorInitializers(
  SymbolTable symbols,
  AstClass owner,
  ConstructorPlan plan,
  List<int> fieldTypes,
  int fieldStart,
) {
  if (plan.redirectTarget >= 0) return;
  final initialized = List<bool>.filled(owner.fields.length, false);
  for (final step in plan.steps) initialized[step.field] = true;
  for (var field = 0; field < owner.fields.length; field++)
    if (!initialized[field] &&
        _requiresInitializer(
          symbols,
          owner.fields[field],
          fieldTypes[fieldStart + field],
        ))
      _initError(
        symbols,
        owner.fields[field].token,
        'missing field initializer',
      );
}

int _initializerField(
  SymbolTable symbols,
  ClassMembers members,
  int fieldStart,
  String name,
  int token,
) {
  var member = lookupMember(members, name);
  if (member < 0 || members.members[member].field < 0)
    _initError(symbols, token, 'initializer requires an own instance field');
  return members.members[member].field - fieldStart;
}

ConstructorPlan planConstructorInitializers(
  SymbolTable symbols,
  int classId,
  List<AstClass> classes,
  AstFunction syntax,
  List<ClassMembers> membersByClass,
  int fieldStart,
  List<List<int>> constructorsByClass,
  List<AstFunction> declarations,
) {
  final owner = classes[classId];
  final members = membersByClass[classId];
  final classFunctions = constructorsByClass[classId];
  var redirectTarget = -1;
  if (syntax.initializers.isNotEmpty &&
      syntax.initializers[0].kind == astRedirectInitializer) {
    var initializer = syntax.initializers[0];
    if (syntax.primary)
      _initError(
        symbols,
        initializer.token,
        'primary constructor cannot redirect',
      );
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
      if (formal.fieldFormal || formal.superFormal)
        _initError(
          symbols,
          formal.token,
          'redirecting constructor cannot have initializing formals',
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
    if (declarations[redirectTarget].factory)
      _initError(
        symbols,
        callee.token,
        'generative redirect requires a generative target',
      );
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
    if (syntax.constant && (field.modifier != 'final' || field.lateVariable))
      _initError(
        symbols,
        field.token,
        'const constructor requires final fields',
      );
    if (redirectTarget < 0 &&
        field.initializer.isNotEmpty &&
        !field.lateVariable) {
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
        fieldStart,
        parameter.name,
        parameter.token,
      );
      if ((initialized[field] & 2) != 0 ||
          initialized[field] != 0 &&
              (syntax.primary || owner.fields[field].modifier == 'final') ||
          owner.fields[field].lateVariable &&
              owner.fields[field].modifier == 'final' &&
              owner.fields[field].initializer.isNotEmpty)
        _initError(symbols, parameter.token, 'field initialized twice');
      initialized[field] |= 2;
      steps.add(ConstructorStep(constructorFormal, p, field));
    }
    p++;
  }
  var i = 0;
  AstExpression? superCall;
  while (i < syntax.initializers.length) {
    var initializer = syntax.initializers[i];
    if (initializer.kind == astSuperInitializer) {
      if (i + 1 != syntax.initializers.length)
        _initError(
          symbols,
          initializer.token,
          'super initializer must be last',
        );
      superCall = initializer.expression;
      i++;
      continue;
    }
    if (initializer.kind != astFieldInitializer)
      _initError(
        symbols,
        initializer.token,
        'unsupported constructor initializer',
      );
    var field = _initializerField(
      symbols,
      members,
      fieldStart,
      initializer.name,
      initializer.token,
    );
    if ((initialized[field] & 6) != 0 ||
        initialized[field] != 0 &&
            (syntax.primary || owner.fields[field].modifier == 'final') ||
        owner.fields[field].lateVariable &&
            owner.fields[field].modifier == 'final' &&
            owner.fields[field].initializer.isNotEmpty)
      _initError(symbols, initializer.token, 'field initialized twice');
    initialized[field] |= 4;
    steps.add(ConstructorStep(constructorExplicit, i, field));
    i++;
  }
  final superclass = classSuperclasses[classId];
  var forwarding = false;
  for (final parameter in syntax.parameters) {
    if (!parameter.superFormal) continue;
    forwarding = true;
    if (superclass == tObject)
      _initError(symbols, parameter.token, 'no corresponding super parameter');
  }
  if (superclass == tObject && superCall == null)
    return ConstructorPlan(steps, -1);
  final call =
      superCall ??
      AstExpression(
        astCall,
        astCallIdentifier,
        <AstExpression>[
          AstExpression(
            astName,
            'super',
            const <AstExpression>[],
            const <AstType>[],
            syntax.token,
          ),
        ],
        const <AstType>[],
        syntax.token,
      );
  final callee = call.children[0];
  if (call.typeArguments.isNotEmpty || callee.typeArguments.isNotEmpty)
    _initError(
      symbols,
      call.token,
      'super constructor cannot have type arguments',
    );
  final name = callee.kind == astMember
      ? constructorSelector(symbols.program, callee.text, callee.token)
      : '';
  if (superclass == tObject) {
    if (name != '' || call.children.length != 1)
      _initError(symbols, call.token, 'Object constructor takes no arguments');
    return ConstructorPlan(steps, -1);
  }
  final parent = typeArgument(superclass);
  final ordinal = lookupConstructor(membersByClass[parent], name);
  if (ordinal < 0)
    _initError(symbols, call.token, 'unknown superclass constructor');
  if (name.startsWith('_') &&
      sourceLibrary(
            symbols.program,
            symbols.program.tokens[syntax.token].source,
          ) !=
          sourceLibrary(
            symbols.program,
            symbols.program.tokens[classes[parent].token].source,
          ))
    _initError(symbols, call.token, 'private superclass constructor');
  final target = constructorsByClass[parent][ordinal];
  if (declarations[target].factory)
    _initError(
      symbols,
      call.token,
      'super invocation requires a generative constructor',
    );
  if (!forwarding) return ConstructorPlan(steps, -1, target, call);
  final formals = declarations[target].parameters;
  final parameters = List<int>.filled(syntax.parameters.length, -1);
  final arguments = <AstExpression>[callee];
  var positional = 0;
  for (var p = 0; p < syntax.parameters.length; p++) {
    final parameter = syntax.parameters[p];
    if (!parameter.superFormal) continue;
    var associated = -1;
    if (parameter.kind == astNamedParameter) {
      for (var q = 0; q < formals.length; q++)
        if (formals[q].kind == astNamedParameter &&
            parameterName(formals[q]) == parameter.name)
          associated = q;
    } else {
      if (positional < formals.length &&
          formals[positional].kind != astNamedParameter)
        associated = positional;
      positional++;
    }
    if (associated < 0)
      _initError(symbols, parameter.token, 'no corresponding super parameter');
    for (var a = 1; a < call.children.length; a++) {
      final argument = call.children[a];
      if (parameter.kind == astNamedParameter
          ? argument.kind == astNamedArgument && argument.text == parameter.name
          : argument.kind != astNamedArgument)
        _initError(
          symbols,
          argument.token,
          'explicit super argument conflicts with super parameter',
        );
    }
    parameters[p] = associated;
    var argument = AstExpression(
      astName,
      parameter.name,
      const <AstExpression>[],
      const <AstType>[],
      parameter.token,
    );
    if (parameter.kind == astNamedParameter)
      argument = AstExpression(
        astNamedArgument,
        parameter.name,
        <AstExpression>[argument],
        const <AstType>[],
        parameter.token,
      );
    arguments.add(argument);
  }
  for (var a = 1; a < call.children.length; a++)
    arguments.add(call.children[a]);
  return ConstructorPlan(
    steps,
    -1,
    target,
    AstExpression(
      call.kind,
      call.text,
      arguments,
      call.typeArguments,
      call.token,
    ),
    parameters,
  );
}

void resolveConstructorSuperParameters(
  SymbolTable symbols,
  List<AstFunction> declarations,
  List<FunctionInfo> signatures,
  List<ConstructorPlan> plans,
  int function,
) {
  final plan = plans[function];
  for (var p = 0; p < plan.superParameters.length; p++) {
    final associated = plan.superParameters[p];
    if (associated < 0) continue;
    final parameter = declarations[function].parameters[p];
    final parentType =
        signatures[plan.superTarget].parameterTypes[associated + 1];
    if (parameter.type.name == '')
      signatures[function].parameterTypes[p + 1] = parentType;
    if (!typeIsSubtype(signatures[function].parameterTypes[p + 1], parentType))
      _initError(
        symbols,
        parameter.token,
        'super parameter type must be a subtype of its target',
      );
  }
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
        syntax[current].token,
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
