import 'ast.dart';
import 'binding.dart';
import 'source.dart';
import 'symbols.dart';
import 'types.dart';

Never _typeError(SymbolTable symbols, int token, String message) {
  sourceError(symbols.program, symbols.program.tokens[token], message);
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
  int function,
) {
  var parameters = _declareTypeParameters(
    symbols,
    syntax.typeParameters,
    -function - 1,
  );
  var uses = <AliasApplication>[];
  var i = 0;
  while (i < parameters.length) {
    var bound = syntax.typeParameters[i].bound;
    typeParameterInfo(parameters[i]).bound = bound == null
        ? nullableType(tObject)
        : _resolveType(symbols, bound, parameters, uses);
    i++;
  }
  _checkParameterCycles(symbols, parameters, syntax.typeParameters);
  for (var use in uses)
    _checkAliasApplication(symbols, use.symbol, use.arguments, use.token, true);
  return parameters;
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
    alias.boundUses = <AliasApplication>[];
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
  alias.bodyUses = <AliasApplication>[];
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

bool _regularAlias(TypeAlias alias, List<int> arguments) {
  var i = 0;
  while (i < alias.parameters.length) {
    var bound = substituteType(
      typeParameterInfo(alias.parameters[i]).bound,
      alias.parameters,
      arguments,
    );
    if (!typeIsSubtype(arguments[i], bound)) return false;
    i++;
  }
  return true;
}

void _checkAliasApplication(
  SymbolTable symbols,
  int symbol,
  List<int> arguments,
  int token,
  bool allowSuperBounded,
) {
  var alias = symbols.aliases[symbols.declarations[symbol].target];
  if (!_regularAlias(alias, arguments)) {
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
    if (!allowSuperBounded || !_regularAlias(alias, inverted))
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
  AliasApplication use,
  int token,
) {
  var actual = <int>[];
  for (var type in use.arguments)
    actual.add(substituteType(type, owner.parameters, arguments));
  _checkAliasApplication(symbols, use.symbol, actual, token, true);
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

bool _simpleRawUse(SymbolTable symbols, AliasApplication use) {
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

void checkAliasApplications(SymbolTable symbols, List<AliasApplication> uses) {
  for (final use in uses)
    _checkAliasApplication(
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
      checkAliasApplications(symbols, alias.boundUses);
      checkAliasApplications(symbols, alias.bodyUses);
    }
    i++;
  }
}

// Resolve the edge first; bounds require the validated class hierarchy.
int resolveSuperinterface(
  SymbolTable symbols,
  AstType syntax,
  List<AliasApplication> uses,
) {
  final type = _resolveType(symbols, syntax, const <int>[], uses, false);
  if (type == tObject || typeIsClass(type)) {
    final declaration =
        symbols.declarations[_typeSymbol(symbols, syntax, const <int>[])];
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
  if (declaration.kind != symbolAlias) return resolved;
  var alias = symbols.aliases[declaration.target];
  if (alias.parameters.isEmpty) return resolved;
  var upper = List<int>.filled(alias.parameters.length, -1);
  var lower = List<int>.filled(alias.parameters.length, -1);
  _objectPatternConstraints(
    alias.template,
    input,
    alias.parameters,
    upper,
    lower,
    true,
  );
  var inferred = <int>[];
  for (var i = 0; i < upper.length; i++)
    inferred.add(upper[i] >= 0 ? upper[i] : lower[i]);
  var arguments = instantiateTypeParameters(alias.parameters, inferred);
  for (var i = 0; i < arguments.length; i++) {
    var bound = substituteType(
      typeParameterInfo(alias.parameters[i]).bound,
      alias.parameters,
      arguments,
    );
    if (!typeIsSubtype(arguments[i], bound))
      arguments[i] = meetTypes(arguments[i], bound);
  }
  _checkAliasApplication(symbols, symbol, arguments, syntax.token, true);
  return substituteType(alias.template, alias.parameters, arguments);
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
    for (
      var i = 0;
      i < source.parameters.length && i < target.parameters.length;
      i++
    )
      _objectPatternConstraints(
        source.parameters[i],
        target.parameters[i],
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
  List<AliasApplication>? uses, [
  bool allowSuperBounded = true,
]) {
  var function = syntax.function;
  if (function != null) {
    bindFunctionTypeParameters(symbols.program, function);
    var parameters = <int>[];
    for (var parameter in function.parameters) {
      if (parameter.metadata.isNotEmpty)
        _typeError(
          symbols,
          parameter.token,
          'function type parameter metadata is not supported',
        );
      if (parameter.kind != astRequiredPositional)
        _typeError(
          symbols,
          parameter.token,
          'optional and named function types are not supported',
        );
      parameters.add(_resolveType(symbols, parameter.type, scope, uses));
    }
    var type = functionType(
      _resolveType(symbols, function.result, scope, uses),
      parameters,
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

bool _nativeContainsParameters(
  SymbolTable symbols,
  AstType syntax,
  List<int> scope,
  List<AliasApplication>? uses,
) {
  var function = syntax.function;
  if (function != null) {
    if (_nativeContainsParameters(symbols, function.result, scope, uses))
      return true;
    for (var parameter in function.parameters)
      if (_nativeContainsParameters(symbols, parameter.type, scope, uses))
        return true;
    return false;
  }
  var name = syntax.name;
  if (name.endsWith('?')) name = name.substring(0, name.length - 1);
  if (typeParameterInScope(scope, name) >= 0)
    return typeContainsParameters(_resolveType(symbols, syntax, scope, uses));
  if (name == 'void' || name == 'dynamic') return false;
  var declaration = symbols.declarations[_typeSymbol(symbols, syntax, scope)];
  if (declaration.kind == symbolNativeType) return false;
  if (declaration.kind == symbolType && declaration.target == tPointer) {
    for (var argument in syntax.arguments)
      if (_nativeContainsParameters(symbols, argument, scope, uses))
        return true;
    return false;
  }
  return typeContainsParameters(_resolveType(symbols, syntax, scope, uses));
}

int _resolveDeclarationType(
  SymbolTable symbols,
  int symbol,
  List<AstType> syntaxArguments,
  int token,
  List<int> scope,
  bool allowSuperBounded,
  List<AliasApplication>? uses,
) {
  var declaration = symbols.declarations[symbol];
  var count = syntaxArguments.length;
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
        AliasApplication(symbol, arguments, token, raw, allowSuperBounded),
      );
    else
      _checkAliasApplication(
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
      (declaration.target < 0 || declaration.target == tPointer);
  if (generic && count > 1 || !generic && count != 0)
    _typeError(
      symbols,
      token,
      'wrong number of type arguments for ' + declaration.name,
    );
  if (declaration.kind == symbolClass) return classType(declaration.target);
  if (declaration.kind == symbolType) {
    if (declaration.target < 0) {
      var element = tDynamic;
      if (count != 0)
        element = _resolveType(symbols, syntaxArguments[0], scope, uses);
      return listType(element);
    }
    if (declaration.target == tPointer && scope.isNotEmpty) {
      for (var argument in syntaxArguments)
        if (_nativeContainsParameters(symbols, argument, scope, uses))
          _typeError(
            symbols,
            token,
            'generic native type templates are not supported',
          );
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
