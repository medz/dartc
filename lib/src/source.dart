import 'host.dart';
import 'scanner.dart';

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

  SourceImport(
    this.uri,
    this.prefix,
    this.target,
    this.start,
    this.end,
    this.exported,
  );
}

class SourceFile {
  String path;
  List<Token> tokens;
  List<SourceImport> imports;

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

bool sourceIs(Token token, String text) {
  return token.kind != tokenString && token.text == text;
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
  i = 0;
  while (i < tokens.length && tokens[i].kind != tokenEnd) {
    bool exported = sourceIs(tokens[i], 'export');
    if (sourceIs(tokens[i], 'library')) {
      while (i < tokens.length && !sourceIs(tokens[i], ';')) i++;
      i++;
      continue;
    }
    if (!exported && !sourceIs(tokens[i], 'import')) break;
    int start = i;
    i++;
    if (tokens[i].kind != tokenString) {
      print('dartc: expected library URI in ' + path);
      hostExit(1);
    }
    String uri = tokens[i].text;
    String prefix = '';
    i++;
    while (i < tokens.length &&
        !sourceIs(tokens[i], ';') &&
        tokens[i].kind != tokenEnd) {
      if (sourceIs(tokens[i], 'as')) {
        i++;
        prefix = tokens[i].text;
      }
      i++;
    }
    if (tokens[i].kind == tokenEnd) {
      print('dartc: unterminated library directive in ' + path);
      hostExit(1);
    }
    i++;
    int target = sourceUnknown;
    if (uri == 'dart:core') {
      target = sourceCore;
    } else if (uri == 'dart:ffi') {
      target = sourceFfi;
    } else if (!uri.startsWith('dart:')) {
      String dependency = directory + uri;
      if (uri.startsWith('/')) dependency = uri;
      target = sourceLoad(program, dependency);
    }
    imports.add(SourceImport(uri, prefix, target, start, i, exported));
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
    program.core = sourceLoad(
      program,
      directory + 'std/core/string_buffer.dart',
    );
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

void sourceError(SourceProgram program, Token token, String message) {
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
