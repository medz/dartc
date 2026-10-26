import 'host.dart';
import 'scanner.dart';
import 'ast.dart';
import 'parser.dart';

const int sourceUnknown = -1;
const int sourceHost = -2;
const int sourceCore = -3;
const int sourceFfi = -4;

class SourceImport {
  String uri;
  String prefix;
  int target;
  int start;
  int end;
  bool exported;
  List<AstCombinator> combinators;

  SourceImport(
    this.uri,
    this.prefix,
    this.target,
    this.start,
    this.end,
    this.exported,
    this.combinators,
  );
}

class SourceFile {
  String path;
  List<Token> tokens;
  List<SourceImport> imports;
  bool system = false;

  SourceFile(this.path, this.tokens, this.imports);
}

class SourceProgram {
  List<SourceFile> files;
  List<int> order;
  List<Token> tokens;
  int entry;
  int runtimeTokens;
  String hostPath;
  int core;

  SourceProgram(
    this.files,
    this.order,
    this.tokens,
    this.entry,
    this.runtimeTokens,
    this.hostPath,
    this.core,
  );
}

String sourcePath(String path) {
  List<String> parts = <String>[];
  bool absolute = path.startsWith('/');
  int start = 0;
  while (start < path.length) {
    int end = path.indexOf('/', start);
    if (end < 0) end = path.length;
    String part = path.substring(start, end);
    if (part != '' && part != '.') {
      if (part == '..' && parts.length > 0 && parts.last != '..') {
        parts.removeLast();
      } else if (part != '..' || !absolute) {
        parts.add(part);
      }
    }
    start = end + 1;
  }
  String result = '';
  if (absolute) result = '/';
  int i = 0;
  while (i < parts.length) {
    if (i > 0) result = result + '/';
    result = result + parts[i];
    i++;
  }
  if (result == '') return '.';
  return result;
}

bool sourceIsSystem(SourceProgram program, int source) {
  if (source == sourceCore || source == sourceFfi) return true;
  return source >= 0 && program.files[source].system;
}

bool sourceIs(Token token, String text) {
  return tokenIs(token, text);
}

bool sourceAllows(SourceImport dependency, String name) {
  var i = 0;
  while (i < dependency.combinators.length) {
    var combinator = dependency.combinators[i];
    var found = false;
    var n = 0;
    while (n < combinator.names.length) {
      if (combinator.names[n] == name) found = true;
      n++;
    }
    if (combinator.show != found) return false;
    i++;
  }
  return true;
}

int sourceLoad(SourceProgram program, String path) {
  path = sourcePath(path);
  if (path == program.hostPath) return sourceHost;
  int i = 0;
  while (i < program.files.length) {
    if (program.files[i].path == path) return i;
    i++;
  }
  int id = program.files.length;
  List<Token> tokens = scanTokens(hostRead(path));
  i = 0;
  while (i < tokens.length) {
    tokens[i].source = id;
    i++;
  }
  List<SourceImport> imports = <SourceImport>[];
  program.files.add(SourceFile(path, tokens, imports));
  String directory = path.substring(0, path.lastIndexOf('/') + 1);
  var paths = <String>[];
  i = 0;
  while (i < program.files.length) {
    paths.add(program.files[i].path);
    i++;
  }
  var parser = Parser(tokens, 0, 0, paths);
  i = 0;
  while (i < tokens.length && tokens[i].kind != tokenEnd) {
    int start = i;
    parser.position = i;
    parserMetadata(parser);
    i = parser.position;
    bool exported = sourceIs(tokens[i], 'export');
    var library = sourceIs(tokens[i], 'library');
    if (!exported && !library && !sourceIs(tokens[i], 'import')) break;
    var kind = astImportDirective;
    if (exported) kind = astExportDirective;
    if (library) kind = astLibraryDirective;
    parser.position = i + 1;
    var directive = parserDirective(parser, kind, i);
    i = parser.position;
    if (library) continue;
    var uri = directive.uri;
    int target = sourceUnknown;
    if (uri == 'dart:core') {
      target = sourceCore;
    } else if (uri == 'dart:ffi') {
      target = sourceFfi;
    } else if (uri.indexOf(':') < 0) {
      String dependency = directory + uri;
      if (uri.startsWith('/')) dependency = uri;
      target = sourceLoad(program, dependency);
    } else {
      sourceError(program, tokens[start], 'unsupported library URI ' + uri);
    }
    imports.add(
      SourceImport(
        uri,
        directive.prefix,
        target,
        start,
        i,
        exported,
        directive.combinators,
      ),
    );
  }
  program.order.add(id);
  return id;
}

SourceProgram collectSources(String input, String runtime) {
  String hostPath = '';
  if (runtime != '') {
    hostPath = sourcePath(
      runtime.substring(0, runtime.lastIndexOf('/') + 1) + 'host.dart',
    );
  }
  SourceProgram program = SourceProgram(
    <SourceFile>[],
    <int>[],
    <Token>[],
    -1,
    0,
    hostPath,
    -1,
  );
  if (runtime != '') {
    int standard = sourceLoad(program, runtime);
    program.runtimeTokens = program.files[standard].tokens.length - 1;
    String directory = runtime.substring(0, runtime.lastIndexOf('/') + 1);
    program.core = sourceLoad(program, directory + 'std/core.dart');
    var work = <int>[program.core];
    var cursor = 0;
    while (cursor < work.length) {
      var source = program.files[work[cursor]];
      cursor++;
      if (source.system) continue;
      source.system = true;
      var dependency = 0;
      while (dependency < source.imports.length) {
        var imported = source.imports[dependency];
        if (imported.exported && imported.target >= 0) {
          work.add(imported.target);
        }
        dependency++;
      }
    }
  }
  program.entry = sourceLoad(program, input);
  int i = 0;
  while (i < program.order.length) {
    List<Token> tokens = program.files[program.order[i]].tokens;
    int t = 0;
    while (t + 1 < tokens.length) {
      program.tokens.add(tokens[t]);
      t++;
    }
    i++;
  }
  program.tokens.add(program.files[program.entry].tokens.last);
  return program;
}

Never sourceError(SourceProgram program, Token token, String message) {
  print(
    'dartc: ' +
        program.files[token.source].path +
        ':' +
        token.start.toString() +
        ': ' +
        message,
  );
  hostExit(1);
}
