import 'ast.dart';
import 'binding.dart';
import 'frontend/parameters.dart';
import 'source.dart';
import 'symbols.dart';
import 'types.dart';

Never _typeError(SymbolTable symbols, int token, String message) {
  sourceError(symbols.program, symbols.program.tokens[token], message);
}

AstExpression resolveStaticShorthand(
  SymbolTable symbols,
  AstExpression expression,
  int context,
) {
  final source = symbols.program.tokens[expression.token].source;
  if (!sourceVersionAtLeast(symbols.program, source, 3, 10))
    _typeError(
      symbols,
      expression.token,
      'dot shorthands require language version 3.10',
    );
  final type = context < 0 ? -1 : typeNonNullable(context);
  var symbol = -1;
  if (type >= 0 &&
      type != tDynamic &&
      type != tVoid &&
      type != tNever &&
      !typeIsParameter(type) &&
      !typeIsFunction(type) &&
      type != schemaHole) {
    for (var i = 0; i < symbols.declarations.length; i++) {
      final declaration = symbols.declarations[i];
      if (typeIsClass(type)
          ? declaration.kind == symbolClass &&
                declaration.target == typeArgument(type)
          : declaration.kind == symbolType &&
                declaration.source ==
                    (type == tPointer ? sourceFfi : sourceCore) &&
                declaration.target == (typeIsList(type) ? -1 : type)) {
        if (declaration.name.startsWith('_') &&
            sourceLibrary(symbols.program, declaration.source) !=
                sourceLibrary(symbols.program, source))
          break;
        symbol = i;
        break;
      }
    }
  }
  if (symbol < 0)
    _typeError(
      symbols,
      expression.token,
      'dot shorthand requires a context with a static namespace',
    );
  final body = expression.children[0];
  var receiver = body;
  while (receiver.kind != astTypeReference) receiver = receiver.children[0];
  receiver.declaration = symbol;
  return body;
}

AstExpression resolveEqualityShorthand(
  SymbolTable symbols,
  String operator,
  AstExpression right,
  int leftType,
) {
  if ((operator == '==' || operator == '!=') &&
      right.kind == astStaticShorthand &&
      right.text != '()')
    return resolveStaticShorthand(symbols, right, leftType);
  return right;
}

List<int> _declareTypeParameters(
  SymbolTable symbols,
  List<AstTypeParameter> syntaxParameters,
  int owner,
) {
  var parameters = <int>[];
  var ordinal = 0;
  for (var syntax in syntaxParameters) {
    var binds =
        syntax.name != '_' ||
        !sourceVersionAtLeast(
          symbols.program,
          symbols.program.tokens[syntax.token].source,
          3,
          7,
        );
    if (binds && typeParameterInScope(parameters, syntax.name) >= 0)
      _typeError(
        symbols,
        syntax.token,
        'duplicate type parameter ' + syntax.name,
      );
    parameters.add(
      newTypeParameter(
        owner,
        ordinal,
        syntax.name,
        binds,
        syntax.bound != null,
      ),
    );
    ordinal++;
  }
  return parameters;
}

void _prepareAliasParameters(SymbolTable symbols, int symbol) {
  var alias = symbols.aliases[symbols.declarations[symbol].target];
  if (alias.parametersReady) return;
  alias.parametersReady = true;
  alias.parameters = _declareTypeParameters(
    symbols,
    alias.syntaxParameters,
    symbol,
  );
}

List<int> resolveFunctionTypeParameters(
  SymbolTable symbols,
  AstFunction syntax,
  int function, [
  List<int> enclosing = const <int>[],
]) {
  var parameters = _declareTypeParameters(
    symbols,
    syntax.typeParameters,
    -function - 1,
  );
  var uses = <TypeApplication>[];
  var i = 0;
  while (i < parameters.length) {
    var bound = syntax.typeParameters[i].bound;
    typeParameterInfo(parameters[i]).bound = bound == null
        ? nullableType(tObject)
        : _resolveType(symbols, bound, <int>[
            ...enclosing,
            ...parameters,
          ], uses);
    i++;
  }
  _checkParameterCycles(symbols, parameters, syntax.typeParameters);
  for (var use in uses)
    _checkTypeApplication(symbols, use.symbol, use.arguments, use.token, true);
  return parameters;
}

void _resolveClassParameters(SymbolTable symbols, int symbol) {
  final declaration = symbols.declarations[symbol];
  if (declaration.parametersReady || declaration.resolvingParameters) return;
  declaration.resolvingParameters = true;
  final syntax = declaration.classSyntax!;
  final parameters = _declareTypeParameters(
    symbols,
    syntax.typeParameters,
    declaration.target,
  );
  classTypeParameters[declaration.target] = parameters;
  declaration.boundUses = <TypeApplication>[];
  for (var i = 0; i < parameters.length; i++) {
    final bound = syntax.typeParameters[i].bound;
    typeParameterInfo(parameters[i]).bound = bound == null
        ? nullableType(tObject)
        : _resolveType(symbols, bound, parameters, declaration.boundUses);
  }
  _checkParameterCycles(symbols, parameters, syntax.typeParameters);
  declaration.resolvingParameters = false;
  declaration.parametersReady = true;
}

void resolveClassTypeParameters(SymbolTable symbols) {
  for (var i = 0; i < symbols.declarations.length; i++)
    if (symbols.declarations[i].kind == symbolClass)
      _resolveClassParameters(symbols, i);
}

List<int> declarationTypeParameters(SymbolTable symbols, int symbol) {
  final declaration = symbols.declarations[symbol];
  return declaration.kind == symbolClass
      ? classTypeParameters[declaration.target]
      : symbols.aliases[declaration.target].parameters;
}

int instantiateDeclarationType(
  SymbolTable symbols,
  int symbol,
  List<int> arguments,
  int token,
) {
  _checkTypeApplication(symbols, symbol, arguments, token, false);
  final declaration = symbols.declarations[symbol];
  if (declaration.kind == symbolClass)
    return classInstanceType(declaration.target, arguments);
  final alias = symbols.aliases[declaration.target];
  return substituteType(alias.template, alias.parameters, arguments);
}

int declarationTypeTemplate(SymbolTable symbols, int symbol) {
  final declaration = symbols.declarations[symbol];
  return declaration.kind == symbolClass
      ? classInstanceType(
          declaration.target,
          classTypeParameters[declaration.target],
        )
      : symbols.aliases[declaration.target].template;
}

int _typeSymbol(SymbolTable symbols, AstType syntax, List<int> scope) {
  var name = syntax.name;
  if (name.endsWith('?')) name = name.substring(0, name.length - 1);
  var prefix = '';
  var dot = name.indexOf('.');
  if (dot >= 0) {
    prefix = name.substring(0, dot);
    name = name.substring(dot + 1);
    if (typeParameterInScope(scope, prefix) >= 0)
      _typeError(
        symbols,
        syntax.token,
        'type parameter cannot be used as a prefix',
      );
  }
  var symbol = resolveSymbol(
    symbols,
    symbols.program.tokens[syntax.token].source,
    name,
    prefix,
  );
  if (symbol == -2) _typeError(symbols, syntax.token, 'ambiguous name ' + name);
  if (symbol < 0)
    _typeError(symbols, syntax.token, 'unknown type ' + syntax.name);
  return symbol;
}

void _checkParameterCycles(
  SymbolTable symbols,
  List<int> parameters,
  List<AstTypeParameter> syntax,
) {
  var start = 0;
  while (start < parameters.length) {
    var seen = List<int>.filled(parameters.length, 0);
    var current = start;
    while (current >= 0) {
      if (seen[current] != 0)
        _typeError(symbols, syntax[start].token, 'cyclic type parameter bound');
      seen[current] = 1;
      var bound = typeNonNullable(typeParameterInfo(parameters[current]).bound);
      current = typeParameterIndex(parameters, bound);
    }
    start++;
  }
}

void _resolveAlias(SymbolTable symbols, int symbol) {
  var declaration = symbols.declarations[symbol];
  var alias = symbols.aliases[declaration.target];
  if (alias.template >= 0) return;
  if (alias.resolving)
    _typeError(
      symbols,
      alias.syntax.token,
      'cyclic type alias ' + declaration.name,
    );
  _prepareAliasParameters(symbols, symbol);
  alias.resolving = true;
  if (alias.parameters.isNotEmpty) {
    alias.boundUses = <TypeApplication>[];
    var i = 0;
    while (i < alias.parameters.length) {
      var syntax = alias.syntaxParameters[i].bound;
      var bound = nullableType(tObject);
      if (syntax != null)
        bound = _resolveType(
          symbols,
          syntax,
          alias.parameters,
          alias.boundUses,
        );
      typeParameterInfo(alias.parameters[i]).bound = bound;
      i++;
    }
    _checkParameterCycles(symbols, alias.parameters, alias.syntaxParameters);
  }
  alias.bodyUses = <TypeApplication>[];
  alias.template = _resolveType(
    symbols,
    alias.syntax,
    alias.parameters,
    alias.bodyUses,
    false,
  );
  for (var parameter in alias.parameters)
    typeParameterInfo(parameter).variance = typeParameterVariance(
      alias.template,
      parameter,
    );
  var head = typeNonNullable(alias.template);
  alias.expandsToParameter =
      typeIsParameter(head) && typeParameterIndex(alias.parameters, head) >= 0;
  if (alias.parameters.isEmpty) alias.type = alias.template;
  alias.resolving = false;
}

int _rawAliasType(TypeAlias alias) {
  if (alias.type < 0) {
    alias.defaultArguments = instantiateTypeParameters(alias.parameters);
    alias.type = substituteType(
      alias.template,
      alias.parameters,
      alias.defaultArguments,
    );
  }
  return alias.type;
}

bool _regularArguments(List<int> parameters, List<int> arguments) {
  var i = 0;
  while (i < parameters.length) {
    var bound = substituteType(
      typeParameterInfo(parameters[i]).bound,
      parameters,
      arguments,
    );
    if (!typeIsSubtype(arguments[i], bound)) return false;
    i++;
  }
  return true;
}

void _checkTypeApplication(
  SymbolTable symbols,
  int symbol,
  List<int> arguments,
  int token,
  bool allowSuperBounded,
) {
  final declaration = symbols.declarations[symbol];
  if (declaration.kind == symbolType) {
    final native = ffiKind(declaration.target);
    final bound = native == ffiPointer ? ffiType(ffiNativeType) : tFunction;
    if (!typeIsSubtype(arguments[0], bound))
      _typeError(
        symbols,
        token,
        'type argument does not satisfy ' + declaration.name + ' bound',
      );
    return;
  }
  if (declaration.kind == symbolClass) {
    final parameters = classTypeParameters[declaration.target];
    if (!_regularArguments(parameters, arguments) &&
        (!allowSuperBounded ||
            !_regularArguments(parameters, <int>[
              for (final argument in arguments) superBoundedType(argument, 1),
            ])))
      _typeError(symbols, token, 'type arguments do not satisfy class bounds');
    return;
  }
  var alias = symbols.aliases[symbols.declarations[symbol].target];
  if (!_regularArguments(alias.parameters, arguments)) {
    var inverted = <int>[];
    if (allowSuperBounded) {
      var i = 0;
      while (i < arguments.length) {
        inverted.add(
          superBoundedType(
            arguments[i],
            typeParameterInfo(alias.parameters[i]).variance,
          ),
        );
        i++;
      }
    }
    if (!allowSuperBounded || !_regularArguments(alias.parameters, inverted))
      _typeError(symbols, token, 'type arguments do not satisfy alias bounds');
  }
  for (var use in alias.boundUses)
    _checkNestedAlias(symbols, alias, arguments, use, token);
  for (var use in alias.bodyUses)
    _checkNestedAlias(symbols, alias, arguments, use, token);
}

void _checkNestedAlias(
  SymbolTable symbols,
  TypeAlias owner,
  List<int> arguments,
  TypeApplication use,
  int token,
) {
  var actual = <int>[];
  for (var type in use.arguments)
    actual.add(substituteType(type, owner.parameters, arguments));
  _checkTypeApplication(symbols, use.symbol, actual, token, true);
}

bool _simpleAlias(SymbolTable symbols, TypeAlias alias) {
  if (alias.simpleBounds >= 0) return alias.simpleBounds == 1;
  alias.simpleBounds = 0;
  for (var parameter in alias.parameters)
    if (typeContainsAnyParameter(
      typeParameterInfo(parameter).bound,
      alias.parameters,
    ))
      return false;
  for (var use in alias.boundUses) {
    for (var argument in use.arguments)
      if (typeContainsAnyParameter(argument, alias.parameters)) return false;
    if (!_simpleRawUse(symbols, use)) return false;
  }
  alias.simpleBounds = 1;
  return true;
}

bool _simpleRawUse(SymbolTable symbols, TypeApplication use) {
  final declaration = symbols.declarations[use.symbol];
  if (declaration.kind == symbolClass) {
    final parameters = classTypeParameters[declaration.target];
    if (use.raw)
      for (final parameter in parameters)
        if (typeContainsAnyParameter(
          typeParameterInfo(parameter).bound,
          parameters,
        ))
          return false;
    return true;
  }
  if (declaration.kind == symbolType) return true;
  var alias = symbols.aliases[symbols.declarations[use.symbol].target];
  if (use.raw && !_simpleAlias(symbols, alias)) return false;
  for (var child in alias.bodyUses)
    if (!_simpleRawUse(symbols, child)) return false;
  return true;
}

void resolveTypeAliasDeclarations(SymbolTable symbols) {
  var i = 0;
  while (i < symbols.declarations.length) {
    if (symbols.declarations[i].kind == symbolAlias)
      _prepareAliasParameters(symbols, i);
    i++;
  }
  i = 0;
  while (i < symbols.declarations.length) {
    if (symbols.declarations[i].kind == symbolAlias) _resolveAlias(symbols, i);
    i++;
  }
}

void checkTypeApplications(SymbolTable symbols, List<TypeApplication> uses) {
  for (final use in uses)
    _checkTypeApplication(
      symbols,
      use.symbol,
      use.arguments,
      use.token,
      use.allowSuperBounded,
    );
}

void checkTypeAliasDeclarations(SymbolTable symbols) {
  var i = 0;
  while (i < symbols.declarations.length) {
    if (symbols.declarations[i].kind == symbolClass) {
      final uses = symbols.declarations[i].boundUses;
      for (final use in uses)
        if (!_simpleRawUse(symbols, use))
          _typeError(
            symbols,
            use.token,
            'raw type with non-simple bounds in type parameter bound',
          );
      checkTypeApplications(symbols, uses);
    }
    if (symbols.declarations[i].kind == symbolAlias) {
      var alias = symbols.aliases[symbols.declarations[i].target];
      for (var use in alias.boundUses) {
        if (!_simpleRawUse(symbols, use))
          _typeError(
            symbols,
            use.token,
            'raw type with non-simple bounds in type parameter bound',
          );
      }
      checkTypeApplications(symbols, alias.boundUses);
      checkTypeApplications(symbols, alias.bodyUses);
    }
    i++;
  }
}

// Resolve the edge first; bounds require the validated class hierarchy.
int resolveSuperinterface(
  SymbolTable symbols,
  AstType syntax,
  List<TypeApplication> uses, [
  List<int> scope = const <int>[],
]) {
  final type = _resolveType(symbols, syntax, scope, uses, false);
  if (typeIsClass(type) && dartTypes[type].arguments.isNotEmpty)
    _typeError(
      symbols,
      syntax.token,
      'generic superinterfaces are not yet supported',
    );
  if (type == tObject || typeIsClass(type)) {
    final declaration =
        symbols.declarations[_typeSymbol(symbols, syntax, scope)];
    if (declaration.kind == symbolAlias &&
        symbols.aliases[declaration.target].expandsToParameter)
      _typeError(
        symbols,
        syntax.token,
        'superinterface alias cannot denote a type parameter',
      );
  }
  return type;
}

int resolveType(
  SymbolTable symbols,
  AstType syntax, [
  List<int> scope = const <int>[],
]) {
  return _resolveType(symbols, syntax, scope, null);
}

// Object patterns infer omitted arguments from the matched value, rather than
// resolving a raw annotation to its default type arguments.
int resolveObjectPatternType(
  SymbolTable symbols,
  AstType syntax,
  int input, [
  List<int> scope = const <int>[],
]) {
  var resolved = resolveType(symbols, syntax, scope);
  if (syntax.arguments.isNotEmpty ||
      syntax.name == 'dynamic' ||
      typeIsParameter(resolved))
    return resolved;
  var symbol = _typeSymbol(symbols, syntax, scope);
  var declaration = symbols.declarations[symbol];
  if (declaration.kind == symbolType && declaration.target < 0) {
    var context = typeNonNullable(input);
    if (typeIsList(context) && !typeIsSubtype(typeArgument(context), tNull))
      return context;
    return resolved;
  }
  if (declaration.kind != symbolAlias && declaration.kind != symbolClass)
    return resolved;
  final original = declarationTypeParameters(symbols, symbol);
  if (original.isEmpty) return resolved;
  final parameters = freshTypeParameters(original, scope);
  var template = declarationTypeTemplate(symbols, symbol);
  if (parameters != original)
    template = substituteType(template, original, parameters);
  var upper = List<int>.filled(parameters.length, -1);
  var lower = List<int>.filled(parameters.length, -1);
  _objectPatternConstraints(template, input, parameters, upper, lower, true);
  var inferred = <int>[];
  for (var i = 0; i < upper.length; i++)
    inferred.add(upper[i] >= 0 ? upper[i] : lower[i]);
  var arguments = instantiateTypeParameters(parameters, inferred);
  for (var i = 0; i < arguments.length; i++) {
    var bound = substituteType(
      typeParameterInfo(parameters[i]).bound,
      parameters,
      arguments,
    );
    if (!typeIsSubtype(arguments[i], bound))
      arguments[i] = meetTypes(arguments[i], bound);
  }
  _checkTypeApplication(symbols, symbol, arguments, syntax.token, true);
  return substituteType(template, parameters, arguments);
}

void _objectPatternConstraints(
  int template,
  int context,
  List<int> parameters,
  List<int> upper,
  List<int> lower,
  bool covariant,
) {
  if (context == tDynamic || context == tVoid || typeIsSubtype(context, tNull))
    return;
  var parameter = typeParameterIndex(parameters, template);
  if (parameter >= 0) {
    var constraints = covariant ? upper : lower;
    var previous = constraints[parameter];
    constraints[parameter] = previous < 0
        ? context
        : covariant
        ? meetTypes(previous, context)
        : joinTypes(previous, context);
  } else if (typeIsNullable(template)) {
    _objectPatternConstraints(
      typeNonNullable(template),
      typeNonNullable(context),
      parameters,
      upper,
      lower,
      covariant,
    );
  } else if (typeIsNullable(context)) {
    _objectPatternConstraints(
      template,
      typeNonNullable(context),
      parameters,
      upper,
      lower,
      covariant,
    );
  } else if (typeIsList(template) && typeIsList(context)) {
    _objectPatternConstraints(
      typeArgument(template),
      typeArgument(context),
      parameters,
      upper,
      lower,
      covariant,
    );
  } else if (typeIsClass(template) &&
      typeIsClass(context) &&
      typeArgument(template) == typeArgument(context)) {
    final source = dartTypes[template].arguments;
    final target = dartTypes[context].arguments;
    for (var i = 0; i < source.length; i++)
      _objectPatternConstraints(
        source[i],
        target[i],
        parameters,
        upper,
        lower,
        covariant,
      );
  } else if (typeIsFunction(template) && typeIsFunction(context)) {
    var source = functionSignature(template);
    var target = functionSignature(context);
    _objectPatternConstraints(
      source.result,
      target.result,
      parameters,
      upper,
      lower,
      covariant,
    );
    for (var i = 0; i < source.parameters.length; i++)
      if (target.corresponding(source, i) >= 0)
        _objectPatternConstraints(
          source.parameters[i],
          target.parameters[target.corresponding(source, i)],
          parameters,
          upper,
          lower,
          !covariant,
        );
  }
}

int _resolveType(
  SymbolTable symbols,
  AstType syntax,
  List<int> scope,
  List<TypeApplication>? uses, [
  bool allowSuperBounded = true,
]) {
  var function = syntax.function;
  if (function != null) {
    bindFunctionTypeParameters(symbols.program, function);
    var parameters = <int>[];
    var required = 0;
    final names = <String>[];
    final requiredNamed = <bool>[];
    for (var parameter in function.parameters) {
      checkParameterModifier(symbols.program, parameter);
      if (parameter.metadata.isNotEmpty)
        _typeError(
          symbols,
          parameter.token,
          'function type parameter metadata is not supported',
        );
      if (parameter.kind == astRequiredPositional) required++;
      if (parameter.kind == astNamedParameter) {
        names.add(parameter.name);
        requiredNamed.add(parameter.required);
      }
      parameters.add(_resolveType(symbols, parameter.type, scope, uses));
    }
    var type = functionType(
      _resolveType(symbols, function.result, scope, uses),
      parameters,
      required,
      names,
      requiredNamed,
    );
    if (syntax.name.endsWith('?')) return nullableType(type);
    return type;
  }
  if (syntax.name.endsWith('?'))
    return nullableType(
      _resolveType(
        symbols,
        AstType(
          syntax.name.substring(0, syntax.name.length - 1),
          syntax.arguments,
          syntax.token,
        ),
        scope,
        uses,
        allowSuperBounded,
      ),
    );
  var count = syntax.arguments.length;
  if (syntax.name == 'void' || syntax.name == 'dynamic') {
    if (count != 0)
      _typeError(symbols, syntax.token, 'type does not accept type arguments');
    return syntax.name == 'void' ? tVoid : tDynamic;
  }
  var parameter = typeParameterInScope(scope, syntax.name);
  if (parameter >= 0) {
    if (count != 0)
      _typeError(
        symbols,
        syntax.token,
        'type parameter does not accept type arguments',
      );
    return parameter;
  }
  return _resolveDeclarationType(
    symbols,
    _typeSymbol(symbols, syntax, scope),
    syntax.arguments,
    syntax.token,
    scope,
    allowSuperBounded,
    uses,
  );
}

int resolveDeclarationType(
  SymbolTable symbols,
  int symbol,
  List<AstType> arguments,
  int token, [
  List<int> scope = const <int>[],
  bool allowSuperBounded = true,
]) {
  return _resolveDeclarationType(
    symbols,
    symbol,
    arguments,
    token,
    scope,
    allowSuperBounded,
    null,
  );
}

int _resolveDeclarationType(
  SymbolTable symbols,
  int symbol,
  List<AstType> syntaxArguments,
  int token,
  List<int> scope,
  bool allowSuperBounded,
  List<TypeApplication>? uses,
) {
  var declaration = symbols.declarations[symbol];
  var count = syntaxArguments.length;
  if (declaration.kind == symbolClass) {
    _resolveClassParameters(symbols, symbol);
    final parameters = classTypeParameters[declaration.target];
    if (count != 0 && count != parameters.length)
      _typeError(
        symbols,
        token,
        'wrong number of type arguments for ' + declaration.name,
      );
    final raw = count == 0 && parameters.isNotEmpty;
    if (raw && declaration.resolvingParameters)
      _typeError(
        symbols,
        token,
        'raw recursive class bounds are not yet supported',
      );
    final arguments = raw
        ? instantiateTypeParameters(parameters)
        : <int>[
            for (final argument in syntaxArguments)
              _resolveType(symbols, argument, scope, uses),
          ];
    if (uses != null)
      uses.add(
        TypeApplication(symbol, arguments, token, raw, allowSuperBounded),
      );
    else
      _checkTypeApplication(
        symbols,
        symbol,
        arguments,
        token,
        allowSuperBounded,
      );
    return classInstanceType(declaration.target, arguments);
  }
  if (declaration.kind == symbolAlias) {
    _resolveAlias(symbols, symbol);
    var alias = symbols.aliases[declaration.target];
    if (count != 0 && count != alias.parameters.length ||
        alias.parameters.isEmpty && count != 0)
      _typeError(
        symbols,
        token,
        'wrong number of type arguments for ' + declaration.name,
      );
    var arguments = <int>[];
    var raw = count == 0 && alias.parameters.isNotEmpty;
    int result;
    if (raw) {
      result = _rawAliasType(alias);
      arguments = alias.defaultArguments;
    } else {
      for (var argument in syntaxArguments)
        arguments.add(_resolveType(symbols, argument, scope, uses));
      result = substituteType(alias.template, alias.parameters, arguments);
    }
    if (uses != null)
      uses.add(
        TypeApplication(symbol, arguments, token, raw, allowSuperBounded),
      );
    else
      _checkTypeApplication(
        symbols,
        symbol,
        arguments,
        token,
        allowSuperBounded,
      );
    return result;
  }
  var generic =
      declaration.kind == symbolType &&
      (declaration.target < 0 ||
          ffiKind(declaration.target) == ffiPointer ||
          ffiKind(declaration.target) == ffiNativeFunction);
  if (generic && count > 1 || !generic && count != 0)
    _typeError(
      symbols,
      token,
      'wrong number of type arguments for ' + declaration.name,
    );
  if (declaration.kind == symbolType) {
    if (declaration.target < 0) {
      var element = tDynamic;
      if (count != 0)
        element = _resolveType(symbols, syntaxArguments[0], scope, uses);
      return listType(element);
    }
    final native = ffiKind(declaration.target);
    if (native == ffiPointer || native == ffiNativeFunction) {
      final bound = native == ffiPointer ? ffiType(ffiNativeType) : tFunction;
      final argument = count == 0
          ? bound
          : _resolveType(symbols, syntaxArguments[0], scope, uses);
      if (uses != null)
        uses.add(
          TypeApplication(symbol, <int>[argument], token, count == 0, false),
        );
      else
        _checkTypeApplication(symbols, symbol, <int>[argument], token, false);
      return ffiType(native, argument);
    }
    return declaration.target;
  }
  _typeError(symbols, token, 'declaration is not a type: ' + declaration.name);
}

int resolvedTypeClassOwner(int type) {
  type = typeNonNullable(type);
  return typeIsClass(type) ? typeArgument(type) : -1;
}

int declarationClassOwner(SymbolTable symbols, int symbol) {
  if (symbol < 0) return -1;
  var declaration = symbols.declarations[symbol];
  if (declaration.kind == symbolClass) return declaration.target;
  if (declaration.kind != symbolAlias) return -1;
  var alias = symbols.aliases[declaration.target];
  if (alias.expandsToParameter) return -1;
  return resolvedTypeClassOwner(alias.template);
}

void checkConstructorValueType(
  SymbolTable symbols,
  int symbol,
  List<AstType> arguments,
  int token,
) {
  final declaration = symbols.declarations[symbol];
  if (declaration.kind == symbolAlias &&
      symbols.aliases[declaration.target].parameters.isNotEmpty)
    sourceError(
      symbols.program,
      symbols.program.tokens[token],
      'generic alias constructor values are not yet supported',
    );
  resolveDeclarationType(
    symbols,
    symbol,
    arguments,
    token,
    const <int>[],
    false,
  );
}
