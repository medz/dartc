import 'source.dart';

const int symbolFunction = 1;
const int symbolGlobal = 2;
const int symbolClass = 3;
const int symbolNativeType = 4;
const int symbolBuiltin = 5;

class DeclarationSymbol {
  int source;
  String name;
  int kind;
  int target;

  DeclarationSymbol(this.source, this.name, this.kind, this.target);
}

class SymbolTable {
  SourceProgram program;
  List<DeclarationSymbol> declarations;

  SymbolTable(this.program, this.declarations);
}

int symbolOwnDeclaration(SymbolTable table, int source, String name) {
  var i = 0;
  while (i < table.declarations.length) {
    var declaration = table.declarations[i];
    if (declaration.source == source && declaration.name == name) return i;
    i++;
  }
  return -1;
}

int declareSymbol(
  SymbolTable table,
  int source,
  String name,
  int kind,
  int target,
) {
  if (symbolOwnDeclaration(table, source, name) >= 0) return -2;
  var symbol = table.declarations.length;
  table.declarations.add(DeclarationSymbol(source, name, kind, target));
  return symbol;
}

int symbolMerge(int left, int right) {
  if (left == -2 || right == -2) return -2;
  if (left == -1) return right;
  if (right == -1 || left == right) return left;
  return -2;
}

int symbolExportedDeclaration(SymbolTable table, int source, String name) {
  if (name.startsWith('_')) return -1;
  var direct = symbolOwnDeclaration(table, source, name);
  if (direct >= 0 || source < 0) return direct;
  var visited = <int>[];
  var i = 0;
  while (i < table.program.files.length) {
    visited.add(0);
    i++;
  }
  var work = <int>[source];
  var cursor = 0;
  var result = -1;
  while (cursor < work.length) {
    var current = work[cursor];
    cursor++;
    if (current >= 0) {
      if (visited[current] != 0) continue;
      visited[current] = 1;
    }
    var declaration = symbolOwnDeclaration(table, current, name);
    if (declaration >= 0) {
      result = symbolMerge(result, declaration);
      if (result == -2) return -2;
    } else if (current >= 0) {
      var imports = table.program.files[current].imports;
      i = 0;
      while (i < imports.length) {
        if (imports[i].exported) work.add(imports[i].target);
        i++;
      }
    }
  }
  return result;
}

int resolveSymbol(SymbolTable table, int source, String name, String prefix) {
  if (prefix == '') {
    var direct = symbolOwnDeclaration(table, source, name);
    if (direct >= 0) return direct;
  }
  var result = -1;
  if (source >= 0) {
    var imports = table.program.files[source].imports;
    var i = 0;
    while (i < imports.length) {
      var dependency = imports[i];
      if (!dependency.exported && dependency.prefix == prefix) {
        var symbol = symbolExportedDeclaration(table, dependency.target, name);
        result = symbolMerge(result, symbol);
        if (result == -2) return -2;
      }
      i++;
    }
  }
  if (result == -1 && prefix == '') {
    return symbolExportedDeclaration(table, sourceCore, name);
  }
  return result;
}
