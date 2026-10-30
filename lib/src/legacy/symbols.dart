import 'ast.dart';
import 'members.dart';
import 'source.dart';

const int symbolFunction = 1;
const int symbolGlobal = 2;
const int symbolClass = 3;
const int symbolBuiltin = 5;
const int symbolType = 6;
const int symbolProperty = 7;
const int symbolAlias = 8;
const int accessorGetter = 1;
const int accessorSetter = 2;

class TypeApplication {
  final int symbol;
  final List<int> arguments;
  final int token;
  final bool raw;
  final bool allowSuperBounded;

  TypeApplication(
    this.symbol,
    this.arguments,
    this.token,
    this.raw,
    this.allowSuperBounded,
  );
}

class TypeAlias {
  final AstType syntax;
  List<AstTypeParameter> syntaxParameters = const <AstTypeParameter>[];
  List<int> parameters = const <int>[];
  List<int> defaultArguments = const <int>[];
  List<TypeApplication> boundUses = const <TypeApplication>[];
  List<TypeApplication> bodyUses = const <TypeApplication>[];
  int template = -1;
  int type = -1;
  int simpleBounds = -1;
  bool parametersReady = false;
  bool resolving = false;
  bool expandsToParameter = false;

  TypeAlias(this.syntax);
}

class DeclarationSymbol {
  int source;
  String name;
  int kind;
  int target;
  int setter = -1;
  int accessors = 0;
  bool writable = false;
  AstClass? classSyntax;
  bool parametersReady = false;
  bool resolvingParameters = false;
  List<TypeApplication> boundUses = const <TypeApplication>[];
  List<InterfaceMember> instanceMembers = const <InterfaceMember>[];

  DeclarationSymbol(this.source, this.name, this.kind, this.target);
}

class SymbolTable {
  SourceProgram program;
  List<DeclarationSymbol> declarations;
  List<TypeAlias> aliases = <TypeAlias>[];
  List<List<int>> sourceDeclarations = <List<int>>[];

  SymbolTable(this.program, this.declarations) {
    var i = 0;
    while (i < declarations.length) {
      _indexDeclaration(this, i);
      i++;
    }
  }
}

void _indexDeclaration(SymbolTable table, int symbol) {
  var scope = table.declarations[symbol].source - sourceFfi;
  while (table.sourceDeclarations.length <= scope) {
    table.sourceDeclarations.add(<int>[]);
  }
  table.sourceDeclarations[scope].add(symbol);
}

int symbolOwnDeclaration(SymbolTable table, int source, String name) {
  source = sourceLibrary(table.program, source);
  var scope = source - sourceFfi;
  if (scope >= table.sourceDeclarations.length) return -1;
  var declarations = table.sourceDeclarations[scope];
  var i = 0;
  while (i < declarations.length) {
    var symbol = declarations[i];
    if (table.declarations[symbol].name == name) return symbol;
    i++;
  }
  return -1;
}

void checkImportPrefixes(SymbolTable table) {
  final program = table.program;
  for (var source = 0; source < program.files.length; source++) {
    final file = program.files[source];
    for (final dependency in file.imports) {
      if (!dependency.exported &&
          dependency.prefix != '' &&
          symbolOwnDeclaration(table, source, dependency.prefix) >= 0)
        sourceError(
          program,
          file.tokens[dependency.start],
          'import prefix conflicts with declaration ' + dependency.prefix,
        );
    }
  }
}

bool symbolWildcardPrefix(SymbolTable table, int source, String prefix) =>
    prefix == '_' && sourceVersionAtLeast(table.program, source, 3, 7);

int declareSymbol(
  SymbolTable table,
  int source,
  String name,
  int kind,
  int target,
) {
  source = sourceLibrary(table.program, source);
  if (symbolOwnDeclaration(table, source, name) >= 0) return -2;
  var symbol = table.declarations.length;
  table.declarations.add(DeclarationSymbol(source, name, kind, target));
  _indexDeclaration(table, symbol);
  return symbol;
}

int declareObjectType(SymbolTable table, int type) {
  var symbol = declareSymbol(table, sourceCore, 'Object', symbolType, type);
  table.declarations[symbol].instanceMembers = const <InterfaceMember>[
    InterfaceMember('==', interfaceMethod),
    InterfaceMember('hashCode', interfaceGetter),
    InterfaceMember('noSuchMethod', interfaceMethod),
    InterfaceMember('runtimeType', interfaceGetter),
    InterfaceMember('toString', interfaceMethod, 'rtObjectToString'),
  ];
  return symbol;
}

int declareAccessor(
  SymbolTable table,
  int source,
  String name,
  int function,
  bool setter,
) {
  source = sourceLibrary(table.program, source);
  var symbol = symbolOwnDeclaration(table, source, name);
  if (symbol < 0) {
    symbol = table.declarations.length;
    table.declarations.add(DeclarationSymbol(source, name, symbolProperty, -1));
    _indexDeclaration(table, symbol);
  }
  var declaration = table.declarations[symbol];
  if (setter) {
    if ((declaration.accessors & accessorSetter) != 0 ||
        declaration.kind != symbolProperty &&
            (declaration.kind != symbolGlobal || declaration.writable)) {
      return -2;
    }
    declaration.accessors |= accessorSetter;
    declaration.setter = function;
  } else {
    if (declaration.kind != symbolProperty ||
        (declaration.accessors & accessorGetter) != 0) {
      return -2;
    }
    declaration.accessors |= accessorGetter;
    declaration.target = function;
  }
  return symbol;
}

bool _symbolHasFacet(DeclarationSymbol declaration, bool writing) {
  if (writing) {
    return (declaration.accessors & accessorSetter) != 0 ||
        declaration.kind == symbolGlobal && declaration.writable;
  }
  return declaration.kind != symbolProperty ||
      (declaration.accessors & accessorGetter) != 0;
}

int symbolMerge(SymbolTable table, int left, int right, bool writing) {
  if (left == -2 || right == -2) return -2;
  if (left == -1) return right;
  if (right == -1 || left == right) return left;
  var leftSource = table.declarations[left].source;
  var rightSource = table.declarations[right].source;
  var leftSystem = sourceIsSystem(table.program, leftSource);
  var rightSystem = sourceIsSystem(table.program, rightSource);
  if (leftSystem && !rightSystem) return right;
  if (!leftSystem && rightSystem) return left;
  var leftFacet = _symbolHasFacet(table.declarations[left], writing);
  var rightFacet = _symbolHasFacet(table.declarations[right], writing);
  if (leftFacet && rightFacet) return -2;
  if (rightFacet) return right;
  return left;
}

int symbolExportedDeclaration(SymbolTable table, int source, String name) {
  return _symbolExportedDeclaration(table, source, name, false);
}

void checkExportConflicts(SymbolTable table) {
  final program = table.program;
  for (var source = 0; source < program.files.length; source++) {
    final file = program.files[source];
    final work = <int>[];
    var token = -1;
    for (final dependency in file.imports) {
      if (!dependency.exported) continue;
      if (token < 0) token = dependency.start;
      work.add(dependency.target);
    }
    if (work.isEmpty) continue;
    final visited = List<bool>.filled(program.files.length - sourceFfi, false);
    final names = <String>[];
    var cursor = 0;
    while (cursor < work.length) {
      final current = sourceLibrary(program, work[cursor++]);
      final scope = current - sourceFfi;
      if (visited[scope]) continue;
      visited[scope] = true;
      if (scope < table.sourceDeclarations.length) {
        for (final symbol in table.sourceDeclarations[scope]) {
          final name = table.declarations[symbol].name;
          if (name.startsWith('_')) continue;
          var index = 0;
          while (index < names.length && names[index] != name) index++;
          if (index == names.length) names.add(name);
        }
      }
      if (current == sourceCore && program.core >= 0) work.add(program.core);
      if (current >= 0) {
        for (final dependency in program.files[current].imports) {
          if (dependency.exported) work.add(dependency.target);
        }
      }
    }
    for (final name in names) {
      if (_symbolExportedDeclaration(table, source, name, false) == -2 ||
          _symbolExportedDeclaration(table, source, name, true) == -2)
        sourceError(
          program,
          file.tokens[token],
          'conflicting exports for ' + name,
        );
    }
  }
}

int _symbolExportedDeclaration(
  SymbolTable table,
  int source,
  String name,
  bool writing,
) {
  source = sourceLibrary(table.program, source);
  if (name.startsWith('_')) return -1;
  var direct = symbolOwnDeclaration(table, source, name);
  if (source == sourceCore && direct < 0 && table.program.core >= 0) {
    source = table.program.core;
    direct = symbolOwnDeclaration(table, source, name);
  }
  if (source < 0 ||
      direct >= 0 && _symbolHasFacet(table.declarations[direct], writing)) {
    return direct;
  }
  final visited = List<int>.filled(table.program.files.length, 0);
  var work = <int>[source];
  var cursor = 0;
  var result = -1;
  while (cursor < work.length) {
    var current = work[cursor];
    cursor++;
    if (current == sourceCore &&
        symbolOwnDeclaration(table, current, name) < 0 &&
        table.program.core >= 0) {
      current = table.program.core;
    }
    if (current >= 0) {
      if (visited[current] != 0) continue;
      visited[current] = 1;
    }
    var declaration = symbolOwnDeclaration(table, current, name);
    if (declaration >= 0) {
      result = symbolMerge(table, result, declaration, writing);
      if (result == -2) return -2;
      if (_symbolHasFacet(table.declarations[declaration], writing)) continue;
    }
    if (current >= 0) {
      var imports = table.program.files[current].imports;
      var i = 0;
      while (i < imports.length) {
        if (imports[i].exported && sourceAllows(imports[i], name)) {
          work.add(imports[i].target);
        }
        i++;
      }
    }
  }
  return result;
}

int resolveSymbol(SymbolTable table, int source, String name, String prefix) {
  return _resolveSymbol(table, source, name, prefix, false);
}

int resolveWriteSymbol(
  SymbolTable table,
  int source,
  String name,
  String prefix,
) {
  return _resolveSymbol(table, source, name, prefix, true);
}

int _resolveSymbol(
  SymbolTable table,
  int source,
  String name,
  String prefix,
  bool writing,
) {
  source = sourceLibrary(table.program, source);
  if (symbolWildcardPrefix(table, source, prefix)) return -1;
  if (prefix == '') {
    var direct = symbolOwnDeclaration(table, source, name);
    if (direct >= 0) return direct;
  }
  var result = -1;
  var explicitCore = false;
  if (source >= 0) {
    var imports = table.program.files[source].imports;
    var i = 0;
    while (i < imports.length) {
      var dependency = imports[i];
      if (!dependency.exported && prefix == '' && dependency.prefix == name)
        return -1;
      if (!dependency.exported && dependency.target == sourceCore) {
        explicitCore = true;
      }
      if (!dependency.exported &&
          dependency.prefix == prefix &&
          sourceAllows(dependency, name)) {
        var symbol = _symbolExportedDeclaration(
          table,
          dependency.target,
          name,
          writing,
        );
        result = symbolMerge(table, result, symbol, writing);
        if (result == -2) return -2;
      }
      i++;
    }
  }
  if (result == -1 && prefix == '' && !explicitCore) {
    return _symbolExportedDeclaration(table, sourceCore, name, writing);
  }
  return result;
}
