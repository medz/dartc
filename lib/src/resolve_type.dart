import 'ast.dart';
import 'source.dart';
import 'symbols.dart';
import 'types.dart';

int resolveType(SymbolTable symbols, AstType syntax) {
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
  return tInt;
}
