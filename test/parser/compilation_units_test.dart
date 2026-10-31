import 'dart:math';

import 'package:dartc/ast.dart';
import 'package:dartc/parser.dart';
import 'package:dartc/scanner.dart';
import 'package:dartc/source.dart';
import 'package:test/test.dart';

ParseResult<CompilationUnit> parse(String text) =>
    parseCompilationUnit(scan(SourceFile(Uri.parse('memory:unit'), text)));

CompilationUnit parsed(String text) {
  final result = parse(text);
  expect(
    result.diagnostics.map((e) => '${e.code}: ${e.span?.text}'),
    isEmpty,
    reason: text,
  );
  return result.node;
}

void main() {
  test('metadata belongs only to the following declaration or enum value', () {
    final unit = parsed(
      '@a class C { @b int first; int second; @c int third; } '
      'class D; @e enum E { @f first, second, @g third }',
    );
    final cls = unit.members.first as ClassDeclaration;
    expect(cls.metadata.single.text, '@a');
    final fields = cls.members.cast<FieldDeclaration>();
    expect(fields[0].variables.metadata.single.text, '@b');
    expect(fields[1].variables.metadata, isEmpty);
    expect(fields[2].variables.metadata.single.text, '@c');
    expect((unit.members[1] as ClassDeclaration).metadata, isEmpty);
    final enumeration = unit.members.last as EnumDeclaration;
    expect(enumeration.metadata.single.text, '@e');
    expect(enumeration.constants[0].metadata.single.text, '@f');
    expect(enumeration.constants[1].metadata, isEmpty);
    expect(enumeration.constants[2].metadata.single.text, '@g');
    expect(walk(unit).whereType<Annotation>().map((a) => a.text), [
      '@a',
      '@b',
      '@c',
      '@e',
      '@f',
      '@g',
    ]);
  });

  test('contextual declaration words can name top-level functions', () {
    for (final name in [
      'import',
      'export',
      'library',
      'part',
      'typedef',
      'extension',
      'mixin',
      'external',
      'abstract',
      'base',
      'interface',
      'sealed',
      'async',
      'sync',
    ]) {
      for (final signature in ['$name()', '$name<T>(T value)']) {
        final unit = parsed('@deprecated $signature => 0;');
        final function = unit.members.single as TopLevelFunctionDeclaration;
        expect(function.name.text, name);
        expect(function.isExternal, isFalse);
        expect(function.metadata.single.text, '@deprecated');
        expect(function.returnType, isNull);
        expect(function.body.text, '=> 0;');
      }
    }
    final unit = parsed('external external<T>(T value);');
    final function = unit.members.single as TopLevelFunctionDeclaration;
    expect(function.isExternal, isTrue);
    expect(function.name.text, 'external');
  });

  test(
    'incomplete contextual functions do not swallow following declarations',
    () {
      for (final name in [
        'import',
        'export',
        'library',
        'part',
        'typedef',
        'mixin',
        'extension',
        'external',
      ]) {
        final result = parse('$name()\nint following = 1;');
        expect(result.hasErrors, isTrue, reason: name);
        final function =
            result.node.members.first as TopLevelFunctionDeclaration;
        expect(function.name.text, name);
        expect(function.body, isA<MissingFunctionBody>());
        final next = result.node.members.last as TopLevelVariableDeclaration;
        expect(next.variables.declarations.single.name.text, 'following');
      }
    },
  );

  test('unit ranges include trivia and preserve the script tag', () {
    expect(parsed(' // empty\n ').members, isEmpty);
    final text = '#!/usr/bin/env dart\n// comment\nvoid main() {}\n';
    final unit = parsed(text);
    expect(unit.text, text);
    expect(unit.scriptTag!.text, '#!/usr/bin/env dart');
    expect(unit.members.single.text, 'void main() {}');
  });

  test('parses ordered library, namespace and part directives', () {
    final unit = parsed(
      "@deprecated library my.lib; import 'a.dart' if (dart.library.io) 'b.dart' if (env.mode == 'fast') 'c.dart' deferred as lib show A, B hide C; export 'public.dart' show A; part 'piece.dart';",
    );
    final library = unit.members[0] as LibraryDirective;
    expect(library.metadata.single.text, '@deprecated');
    expect(library.name!.components.map((n) => n.text), ['my', 'lib']);
    final import = unit.members[1] as ImportDirective;
    expect(import.uri.text, "'a.dart'");
    expect(import.isDeferred, isTrue);
    expect(import.prefix!.text, 'lib');
    expect(import.configurations, hasLength(2));
    expect(import.configurations.first.value, isNull);
    expect(import.configurations.last.value!.text, "'fast'");
    expect(import.combinators.first.names.map((n) => n.text), ['A', 'B']);
    expect(import.combinators.last.kind, NamespaceCombinatorKind.hide);
    expect(unit.members[2], isA<ExportDirective>());
    expect(unit.members[3], isA<PartDirective>());
    expect(
      (parsed('library;').members.single as LibraryDirective).name,
      isNull,
    );
    expect(
      (parsed("part of 'main.dart';").members.single as PartOfDirective).target,
      isA<StringExpression>(),
    );
    expect(
      (parsed('part of my.lib;').members.single as PartOfDirective).target,
      isA<DottedName>(),
    );
  });

  test('retains raw, adjacent and multiline directive strings', () {
    for (final uri in [r"r'a\b.dart'", "'a' 'b.dart'", "'''a.dart''' "]) {
      final import = parsed('import $uri;').members.single as ImportDirective;
      expect(import.uri.text.trim(), uri.trim());
    }
    expect(parse(r"import '${name}';").hasErrors, isTrue);
    expect(parse('import 1;').hasErrors, isTrue);
  });

  test(
    'parses top-level functions, generics, accessors and external bodies',
    () {
      final unit = parsed(
        '@A() T identity<T>(T x) => x; external int native(int x); int get count => 1; set count(int x) {} void main() async { await run(); }',
      );
      final function = unit.members[0] as TopLevelFunctionDeclaration;
      expect(function.metadata.single.text, '@A()');
      expect(function.returnType!.text, 'T');
      expect(function.typeParameters!.text, '<T>');
      expect(function.parameters.text, '(T x)');
      expect(function.body.text, '=> x;');
      final external = unit.members[1] as TopLevelFunctionDeclaration;
      expect(external.isExternal, isTrue);
      expect(external.body, isA<EmptyFunctionBody>());
      expect(unit.members[2], isA<TopLevelGetterDeclaration>());
      expect(unit.members[3], isA<TopLevelSetterDeclaration>());
      expect(
        (unit.members[4] as TopLevelFunctionDeclaration).body,
        isA<ModifiedBlockFunctionBody>(),
      );
    },
  );

  test('parses top-level variables with metadata and nested initializers', () {
    final unit = parsed(
      '@A() final int x = 1, y = 2; late String name; var fn = (int x) => x; external int value;',
    );
    final declaration = unit.members.first as TopLevelVariableDeclaration;
    expect(declaration.variables.metadata.single.text, '@A()');
    expect(declaration.variables.type!.text, 'int');
    expect(declaration.variables.declarations.map((d) => d.name.text), [
      'x',
      'y',
    ]);
    expect(
      (unit.members[1] as TopLevelVariableDeclaration).variables.isLate,
      isTrue,
    );
    expect(
      (unit.members[2] as TopLevelVariableDeclaration)
          .variables
          .declarations
          .single
          .initializer,
      isA<FunctionExpression>(),
    );
    expect((unit.members[3] as TopLevelVariableDeclaration).isExternal, isTrue);
    expect(
      parsed('int? x = flag ? 1 : null;').members.single,
      isA<TopLevelVariableDeclaration>(),
    );
  });

  test('parses type aliases in both declaration forms', () {
    final unit = parsed(
      '@A() typedef Mapper<T> = T Function(T); typedef int Compare<T>(T a, T b); typedef Callback();',
    );
    final alias = unit.members[0] as TypeAliasDeclaration;
    expect(alias.metadata.single.text, '@A()');
    expect(alias.name.text, 'Mapper');
    expect(alias.typeParameters!.text, '<T>');
    expect(alias.type, isA<FunctionTypeAnnotation>());
    final legacy = unit.members[1] as FunctionTypeAliasDeclaration;
    expect(legacy.returnType!.text, 'int');
    expect(legacy.name.text, 'Compare');
    expect(legacy.parameters.parameters, hasLength(2));
    expect(
      (unit.members[2] as FunctionTypeAliasDeclaration).returnType,
      isNull,
    );
  });

  test('reports misplaced directives and malformed declarations', () {
    for (final text in [
      "void f() {} import 'a.dart';",
      "part 'a.dart'; import 'b.dart';",
      'library a; library b;',
      "part of a; import 'b.dart';",
      'void f();',
      'external void f() {}',
      'int get x<T> => 1;',
      'typedef int Alias = String;',
      "import 'a.dart' deferred;",
      "import 'a.dart' show ;",
      'typedef F = ;',
    ]) {
      expect(parse(text).hasErrors, isTrue, reason: text);
    }
    final result = parse('int x = ; void next() {}');
    expect(result.hasErrors, isTrue);
    expect(result.node.members.last, isA<TopLevelFunctionDeclaration>());
    expect(
      (result.node.members.last as TopLevelFunctionDeclaration).name.text,
      'next',
    );
  });

  test('preserves source ranges and tokens during recovery', () {
    final random = Random(3812);
    const fragments = [
      'library',
      'import',
      'export',
      'part',
      'of',
      "'a'",
      'if',
      'as',
      'deferred',
      'show',
      'hide',
      'typedef',
      'void',
      'int',
      'var',
      'final',
      'late',
      'const',
      'get',
      'set',
      '@',
      'x',
      'y',
      '(',
      ')',
      '{',
      '}',
      '[',
      ']',
      '<',
      '>',
      '?',
      ',',
      '.',
      ';',
      '=',
      '=>',
    ];
    for (var i = 0; i < 500; i++) {
      final text = List.generate(
        random.nextInt(35),
        (_) => fragments[random.nextInt(fragments.length)],
      ).join(' ');
      final input = scan(SourceFile(Uri.parse('memory:malformed'), text));
      final tokens = [...input.tokens];
      final result = parseCompilationUnit(input);
      expect(input.tokens, orderedEquals(tokens));
      for (final node in walk(result.node)) {
        expect(node.source, same(input.source));
        expect(node.start, inInclusiveRange(0, text.length));
        expect(node.end, inInclusiveRange(node.start, text.length));
      }
    }
  });
}
