import 'ast.dart';
import 'binding.dart';
import 'source.dart';
import 'symbols.dart';
import 'types.dart';

int resolveType(SymbolTable symbols, AstType syntax) {
  var function = syntax.function;
  if (function != null) {
    bindFunctionTypeParameters(symbols.program, function);
    var parameters = <int>[];
    for (var parameter in function.parameters) {
      if (parameter.metadata.isNotEmpty)
        sourceError(
          symbols.program,
          symbols.program.tokens[parameter.token],
          'function type parameter metadata is not supported',
        );
      if (parameter.kind != astRequiredPositional)
        sourceError(
          symbols.program,
          symbols.program.tokens[parameter.token],
          'optional and named function types are not supported',
        );
      parameters.add(resolveType(symbols, parameter.type));
    }
    var type = functionType(resolveType(symbols, function.result), parameters);
    if (syntax.name.endsWith('?')) return nullableType(type);
    return type;
  }
  if (syntax.name.endsWith('?')) {
    return nullableType(
      resolveType(
        symbols,
        AstType(
          syntax.name.substring(0, syntax.name.length - 1),
          syntax.arguments,
          syntax.token,
        ),
      ),
    );
  }
  var token = symbols.program.tokens[syntax.token];
  var count = syntax.arguments.length;
  if (syntax.name == 'void' || syntax.name == 'dynamic') {
    if (count != 0) {
      sourceError(
        symbols.program,
        token,
        'type does not accept type arguments',
      );
    }
    if (syntax.name == 'void') return tVoid;
    return tDynamic;
  }
  var name = syntax.name;
  var prefix = '';
  var dot = name.indexOf('.');
  if (dot >= 0) {
    prefix = name.substring(0, dot);
    name = name.substring(dot + 1);
  }
  var symbol = resolveSymbol(symbols, token.source, name, prefix);
  if (symbol == -2) {
    sourceError(symbols.program, token, 'ambiguous name ' + name);
  }
  if (symbol < 0) {
    sourceError(symbols.program, token, 'unknown type ' + syntax.name);
  }
  var declaration = symbols.declarations[symbol];
  var generic =
      declaration.kind == symbolType &&
      (declaration.target < 0 || declaration.target == tPointer);
  if (generic && count > 1 || !generic && count != 0) {
    sourceError(
      symbols.program,
      token,
      'wrong number of type arguments for ' + syntax.name,
    );
  }
  if (declaration.kind == symbolClass) return classType(declaration.target);
  if (declaration.kind == symbolAlias) {
    var alias = symbols.aliases[declaration.target];
    if (alias.type >= 0) return alias.type;
    if (alias.resolving)
      sourceError(
        symbols.program,
        symbols.program.tokens[alias.syntax.token],
        'cyclic type alias ' + declaration.name,
      );
    alias.resolving = true;
    alias.type = resolveType(symbols, alias.syntax);
    alias.resolving = false;
    return alias.type;
  }
  if (declaration.kind == symbolType) {
    if (declaration.target < 0) {
      var element = tDynamic;
      if (syntax.arguments.length != 0) {
        element = resolveType(symbols, syntax.arguments[0]);
      }
      return listType(element);
    }
    return declaration.target;
  }
  sourceError(
    symbols.program,
    token,
    'declaration is not a type: ' + syntax.name,
  );
}

int resolvedClassOwner(SymbolTable symbols, int symbol) {
  if (symbol < 0) return -1;
  var declaration = symbols.declarations[symbol];
  if (declaration.kind == symbolClass) return declaration.target;
  if (declaration.kind == symbolAlias) {
    var type = typeNonNullable(symbols.aliases[declaration.target].type);
    if (typeIsClass(type)) return typeArgument(type);
  }
  return -1;
}
