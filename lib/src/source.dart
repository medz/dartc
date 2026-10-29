import 'host.dart';
import 'scanner.dart';
import 'ast.dart';
import 'diagnostic.dart';
import 'parser.dart';
import 'source_uri.dart';
import 'source_bundle.dart';
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
  int library = -1;
  String libraryName = '';
  List<Token> tokens;
  List<SourceImport> imports;
  bool system = false;
  int languageMajor = 3;
  int languageMinor = 13;
  int languageOffset = -1;

  SourceFile(this.path, this.tokens, this.imports);
}

int sourceLibrary(SourceProgram program, int source) {
  if (source < 0) return source;
  return program.files[source].library;
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
  SourceBundle? bundle;
  List<String> libraries = const <String>[];

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
  source = sourceLibrary(program, source);
  if (source == sourceCore || source == sourceFfi) return true;
  return source >= 0 && program.files[source].system;
}

String sourceReferenceUri(String base, String reference) {
  var scheme = sourceUriScheme(reference);
  if (scheme == 'package') {
    var package = sourcePackageUri(reference);
    return 'package:' + package.name + '/' + package.path;
  }
  if (scheme == '' && sourceUriScheme(base) == 'package') {
    var package = sourcePackageRelative(sourcePackageUri(base), reference);
    return 'package:' + package.name + '/' + package.path;
  }
  if (scheme == '' || scheme == 'file') {
    if (scheme == 'file') base = 'file:///';
    return sourceResolveFileUri(base, reference);
  }
  return reference;
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

// These are the system-library entries provided by the current target ports.
// FFI advertises its existing restricted declarations, not the complete SDK API.
List<String> sourceTargetLibraries(int target) {
  if (target == 0 || target == 1) return const <String>['core', 'ffi'];
  print('Unsupported source target: ' + target.toString());
  hostExit(1);
}

String sourceDirectiveUri(SourceProgram program, AstDirective directive) {
  var i = 0;
  while (i < directive.conditions.length) {
    var condition = directive.conditions[i];
    if (condition.key.startsWith('dart.library.')) {
      var name = condition.key.substring(13);
      var library = 0;
      while (library < program.libraries.length) {
        if (program.libraries[library] == name && condition.value == 'true')
          return condition.uri;
        library++;
      }
    }
    i++;
  }
  return directive.uri;
}

int sourceLoad(
  SourceProgram program,
  String uri, [
  bool implementation = false,
  int library = -1,
]) {
  SourcePackageUri? package;
  if (sourceUriScheme(uri) == 'package') {
    package = sourcePackageUri(uri);
    uri = 'package:' + package.name + '/' + package.path;
  }
  if (uri == program.hostUri) return sourceHost;
  int i = 0;
  while (i < program.files.length) {
    if (program.files[i].uri == uri) {
      var file = program.files[i];
      if (library >= 0) {
        if (file.library == i)
          sourceError(
            program,
            file.tokens[0],
            'library cannot be used as a part',
          );
        if (file.library != library)
          sourceError(
            program,
            file.tokens[0],
            'part belongs to more than one library',
          );
        sourceError(program, file.tokens[0], 'part used more than once');
      }
      if (file.library != i)
        sourceError(
          program,
          file.tokens[0],
          'part cannot be imported as a library',
        );
      return i;
    }
    i++;
  }
  final config = program.packages;
  final bundle = program.bundle;
  String? text;
  if (bundle != null && implementation) {
    text = bundle.read(uri);
    if (text == null) throw Diagnostic('dartc: missing bundled source: ' + uri);
  } else if (bundle != null &&
      package != null &&
      (config == null || sourcePackageNamed(config, package.name) == null)) {
    text = bundle.read(uri);
  }
  String path;
  if (package != null && text != null) {
    path = uri;
  } else if (package != null) {
    if (config == null) {
      print('dartc: no package configuration for ' + uri);
      hostExit(1);
    }
    path = resolvePackageUri(config, package);
  } else {
    path = sourceUriPath('/', uri);
  }
  int id = program.files.length;
  var scanner = Scanner(text ?? hostRead(path), <Token>[], 0);
  scanner.path = path;
  var packages = program.packages;
  if (text == null && !implementation && packages != null) {
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
  file.library = id;
  if (library >= 0) file.library = library;
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
  var partOf = false;
  var librarySeen = false;
  var partsSeen = false;
  if (library >= 0) {
    var parent = program.files[library];
    if (file.languageMajor != parent.languageMajor ||
        file.languageMinor != parent.languageMinor ||
        (file.languageOffset >= 0) != (parent.languageOffset >= 0))
      sourceError(
        program,
        tokens[0],
        'part language version must match its library',
      );
  }
  i = 0;
  while (i < tokens.length && tokens[i].kind != tokenEnd) {
    int start = i;
    parser.position = i;
    parserMetadata(parser);
    i = parser.position;
    var kind = 0;
    if (sourceIs(tokens[i], 'import')) kind = astImportDirective;
    if (sourceIs(tokens[i], 'export')) kind = astExportDirective;
    if (sourceIs(tokens[i], 'library')) kind = astLibraryDirective;
    if (parserPartDirective(parser)) kind = astPartDirective;
    if (kind == 0) break;
    parser.position = i + 1;
    if (kind == astPartDirective && parserTake(parser, 'of')) {
      kind = astPartOfNameDirective;
      if (parser.tokens[parser.position].kind == tokenString ||
          parser.tokens[parser.position].kind == tokenStringPart)
        kind = astPartOfUriDirective;
    }
    var directive = parserDirective(parser, kind, i);
    i = parser.position;
    if (kind == astPartOfUriDirective || kind == astPartOfNameDirective) {
      if (library < 0)
        sourceError(
          program,
          tokens[start],
          'part cannot be imported as a library',
        );
      if (partOf)
        sourceError(
          program,
          tokens[start],
          'part must have one part of directive',
        );
      var parent = program.files[library];
      if (kind == astPartOfUriDirective) {
        if (sourceReferenceUri(uri, directive.uri) != parent.uri)
          sourceError(
            program,
            tokens[start],
            'part of URI does not match its library',
          );
      } else if (parent.libraryName == '' ||
          directive.uri != parent.libraryName) {
        sourceError(
          program,
          tokens[start],
          'part of name does not match its library',
        );
      }
      partOf = true;
      continue;
    }
    if (library >= 0)
      sourceError(
        program,
        tokens[start],
        'part of must be the only directive in a part',
      );
    if (kind == astLibraryDirective) {
      if (librarySeen || imports.isNotEmpty || partsSeen)
        sourceError(
          program,
          tokens[start],
          'library directive must come first',
        );
      librarySeen = true;
      file.libraryName = directive.uri;
      if (directive.uri == '' && !sourceVersionAtLeast(program, id, 2, 19))
        sourceError(
          program,
          tokens[start],
          'unnamed library requires language version 2.19',
        );
      continue;
    }
    var reference = sourceDirectiveUri(program, directive);
    if (kind == astPartDirective) {
      var scheme = sourceUriScheme(reference);
      if (scheme != '' && scheme != 'file' && scheme != 'package')
        sourceError(
          program,
          tokens[start],
          'unsupported part URI ' + reference,
        );
      partsSeen = true;
      var part = sourceLoad(
        program,
        sourceReferenceUri(uri, reference),
        implementation,
        id,
      );
      if (part < 0)
        sourceError(program, tokens[start], 'part must be a Dart source file');
      continue;
    }
    if (partsSeen)
      sourceError(
        program,
        tokens[start],
        'imports and exports must precede parts',
      );
    int target = sourceUnknown;
    if (reference == 'dart:core') {
      target = sourceCore;
    } else if (reference == 'dart:ffi') {
      target = sourceFfi;
    } else {
      var scheme = sourceUriScheme(reference);
      if (scheme != '' && scheme != 'package' && scheme != 'file')
        sourceError(
          program,
          tokens[start],
          'unsupported library URI ' + reference,
        );
      target = sourceLoad(
        program,
        sourceReferenceUri(uri, reference),
        implementation,
      );
    }
    imports.add(
      SourceImport(
        reference,
        directive.prefix,
        target,
        start,
        i,
        kind == astExportDirective,
        directive.combinators,
      ),
    );
  }
  if (library >= 0 && !partOf)
    sourceError(program, tokens[0], 'part must begin with a part of directive');
  program.order.add(id);
  return id;
}

SourceProgram collectSources(
  String input,
  String runtime, [
  PackageConfig? packages,
  int target = 0,
  SourceBundle? bundle,
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
  program.bundle = bundle;
  program.libraries = sourceTargetLibraries(target);
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
  throw Diagnostic(
    'dartc: ' +
        program.files[token.source].path +
        ':' +
        token.start.toString() +
        ': ' +
        message,
  );
}
