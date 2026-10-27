import 'host.dart';
import 'scanner.dart';
import 'ast.dart';
import 'parser.dart';
import 'source_uri.dart';
import 'package_config.dart';

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
  String uri = '';
  List<Token> tokens;
  List<SourceImport> imports;
  bool system = false;
  int languageMajor = 3;
  int languageMinor = 13;
  int languageOffset = -1;

  SourceFile(this.path, this.tokens, this.imports);
}

class SourceProgram {
  List<SourceFile> files;
  List<int> order;
  List<Token> tokens;
  int entry;
  int runtimeTokens;
  String hostUri;
  int core;
  PackageConfig? packages;

  SourceProgram(
    this.files,
    this.order,
    this.tokens,
    this.entry,
    this.runtimeTokens,
    this.hostUri,
    this.core,
  );
}

bool sourceVersionAtLeast(
  SourceProgram program,
  int source,
  int major,
  int minor,
) {
  var languageMajor = 3;
  var languageMinor = 13;
  if (source >= 0) {
    languageMajor = program.files[source].languageMajor;
    languageMinor = program.files[source].languageMinor;
  }
  return languageMajor > major ||
      languageMajor == major && languageMinor >= minor;
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

int sourceLoad(
  SourceProgram program,
  String uri, [
  bool implementation = false,
]) {
  SourcePackageUri? package;
  if (sourceUriScheme(uri) == 'package') {
    package = sourcePackageUri(uri);
    uri = 'package:' + package.name + '/' + package.path;
  }
  if (uri == program.hostUri) return sourceHost;
  int i = 0;
  while (i < program.files.length) {
    if (program.files[i].uri == uri) return i;
    i++;
  }
  String path;
  if (package != null) {
    var config = program.packages;
    if (config == null) {
      print('dartc: no package configuration for ' + uri);
      hostExit(1);
    }
    path = resolvePackageUri(config, package);
  } else {
    path = sourceUriPath('/', uri);
  }
  int id = program.files.length;
  var scanner = Scanner(hostRead(path), <Token>[], 0);
  scanner.path = path;
  var packages = program.packages;
  if (!implementation && packages != null) {
    var package = sourcePackageForFile(packages, path);
    if (package != null && package.languageMajor >= 0) {
      var major = package.languageMajor;
      var minor = package.languageMinor;
      if (major < 2 ||
          major == 2 && minor < 12 ||
          major > 3 ||
          major == 3 && minor > 13)
        packageConfigError(
          packages,
          'unsupported language version ' +
              major.toString() +
              '.' +
              minor.toString() +
              ' for package ' +
              package.name +
              ' in ' +
              path,
        );
      scanner.languageMajor = major;
      scanner.languageMinor = minor;
    }
  }
  scanHeader(scanner);
  List<SourceImport> imports = <SourceImport>[];
  var file = SourceFile(path, scanner.tokens, imports);
  file.uri = uri;
  file.languageMajor = scanner.languageMajor;
  file.languageMinor = scanner.languageMinor;
  file.languageOffset = scanner.languageOffset;
  program.files.add(file);
  if (!sourceVersionAtLeast(program, id, 2, 12) ||
      sourceVersionAtLeast(program, id, 3, 14)) {
    sourceError(
      program,
      Token(tokenSymbol, '', file.languageOffset, file.languageOffset, id),
      'unsupported language version ' +
          file.languageMajor.toString() +
          '.' +
          file.languageMinor.toString() +
          '; supported versions are 2.12 through 3.13',
    );
  }
  List<Token> tokens = scanTokens(scanner);
  i = 0;
  while (i < tokens.length) {
    tokens[i].source = id;
    i++;
  }
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
    if (library) {
      if (directive.uri == '' && !sourceVersionAtLeast(program, id, 2, 19)) {
        sourceError(
          program,
          tokens[start],
          'unnamed library requires language version 2.19',
        );
      }
      continue;
    }
    var reference = directive.uri;
    int target = sourceUnknown;
    if (reference == 'dart:core') {
      target = sourceCore;
    } else if (reference == 'dart:ffi') {
      target = sourceFfi;
    } else {
      var scheme = sourceUriScheme(reference);
      if (scheme == 'package') {
        target = sourceLoad(program, reference, implementation);
      } else if (scheme == '' && package != null) {
        var imported = sourcePackageRelative(package, reference);
        target = sourceLoad(
          program,
          'package:' + imported.name + '/' + imported.path,
          implementation,
        );
      } else if (scheme == '' || scheme == 'file') {
        var base = uri;
        if (scheme == 'file') base = 'file:///';
        target = sourceLoad(
          program,
          sourceResolveFileUri(base, reference),
          implementation,
        );
      } else {
        sourceError(
          program,
          tokens[start],
          'unsupported library URI ' + reference,
        );
      }
    }

    imports.add(
      SourceImport(
        reference,
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

SourceProgram collectSources(
  String input,
  String runtime, [
  PackageConfig? packages,
]) {
  String hostUri = '';
  if (runtime != '') hostUri = sourceResolveFileUri(runtime, 'host.dart');
  SourceProgram program = SourceProgram(
    <SourceFile>[],
    <int>[],
    <Token>[],
    -1,
    0,
    hostUri,
    -1,
  );
  program.packages = packages;
  if (runtime != '') {
    int standard = sourceLoad(program, runtime, true);
    program.runtimeTokens = program.files[standard].tokens.length - 1;
    program.core = sourceLoad(
      program,
      sourceResolveFileUri(runtime, 'std/core.dart'),
      true,
    );
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
