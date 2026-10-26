import 'ast.dart';
import 'resolve_type.dart';
import 'source.dart';
import 'symbols.dart';
import 'types.dart';

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
      var required = _requiresInitializer(symbols, field);
      if (required && field.initializer.isEmpty && owner.constructors.isEmpty) {
        _initError(symbols, field.token, 'missing field initializer');
      }
      var c = 0;
      while (c < owner.constructors.length) {
        var parameters = owner.constructors[c].parameters;
        var initialized = false;
        var p = 0;
        while (p < parameters.length) {
          var parameter = parameters[p];
          if (parameter.fieldFormal && parameter.name == field.name) {
            initialized = true;
            if (field.modifier == 'final' && field.initializer.isNotEmpty) {
              _initError(symbols, parameter.token, 'field initialized twice');
            }
          }
          p++;
        }
        if (required && field.initializer.isEmpty && !initialized) {
          _initError(symbols, field.token, 'missing field initializer');
        }
        c++;
      }
      f++;
    }
    i++;
  }
}
