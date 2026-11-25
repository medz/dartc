import 'dart:io';

import 'package:dartc/driver.dart';
import 'package:dartc/source.dart';
import 'package:test/test.dart';

import '../support/compiler.dart';

void main() {
  Future<SourceProgram> loadFiles(Map<String, String> files) async {
    final directory = writeSources(files);
    return loadProgram('${directory.path}/main.dart', sdk: await packagedSdk());
  }

  test('loads a library with its parts', () async {
    final program = await loadFiles({
      'main.dart': "part 'part.dart';\nvoid main() {}",
      'part.dart': "part of 'main.dart';\nvoid f() {}",
    });
    expect(program.main.units.map((unit) => unit.path.split('/').last), [
      'main.dart',
      'part.dart',
    ]);
    expect(program.main.element.entryPoint, isNotNull);
  });

  test('follows a symbolic link', () async {
    final directory = writeSources({'real/main.dart': 'void main() {}'});
    final link = Link('${directory.path}/main.dart')
      ..createSync('${directory.path}/real/main.dart');
    final program = await loadProgram(link.path, sdk: await packagedSdk());
    expect(program.main.units.single.path, endsWith('/real/main.dart'));
  });

  test('positions count from one', () async {
    await expectLater(
      load('void main() { y; }\n  z'),
      throwsA(
        isA<CompileFailure>().having(
          (failure) => {
            for (final problem in failure.problems)
              (problem.line, problem.column),
          },
          'positions',
          containsAll([(1, 15), (2, 3)]),
        ),
      ),
    );
  });

  group('errors cannot be hidden', () {
    void hides(String how, Map<String, String> files, int line) {
      test(how, () async {
        await expectLater(
          loadFiles({'main.dart': 'void main() {}', ...files}),
          throwsA(
            isA<CompileFailure>().having(
              (failure) => [
                for (final problem in failure.problems)
                  (problem.line, problem.column),
              ],
              'positions',
              [(line, 9)],
            ),
          ),
        );
      });
    }

    const error = 'int x = "";';
    hides('by a comment on the line', {
      'main.dart': 'void main() {}\n$error // ignore: invalid_assignment',
    }, 2);
    hides('by a comment above', {
      'main.dart': 'void main() {}\n// ignore: invalid_assignment\n$error',
    }, 3);
    hides('by a comment for the file', {
      'main.dart':
          '// ignore_for_file: invalid_assignment, type=lint\n'
          'void main() {}\n$error',
    }, 3);
    hides('by a comment at the end of the file', {
      'main.dart':
          'void main() {}\n$error\n// ignore_for_file: invalid_assignment',
    }, 2);
    hides('in an imported file', {
      'main.dart': "import 'a.dart';\nvoid main() => a();",
      'a.dart': 'void a() {}\n$error // ignore: invalid_assignment',
    }, 2);
    hides('by options', {
      'main.dart': 'void main() {}\n$error',
      'analysis_options.yaml':
          'analyzer:\n  errors:\n    invalid_assignment: ignore\n',
    }, 2);
    hides('by excluding files', {
      'main.dart': 'void main() {}\n$error',
      'analysis_options.yaml': 'analyzer:\n  exclude:\n    - "**"\n',
    }, 2);
  });

  test('warnings do not stop compilation', () async {
    await load('void main() { var unused = 1; }');
  });

  test('errors in imported, exported and part files are found', () async {
    for (final directive in ['import', 'export']) {
      await expectLater(
        loadFiles({
          'main.dart': "import 'a.dart';\nvoid main() => a();",
          'a.dart': "$directive 'b.dart';\nvoid a() {}",
          'b.dart': 'int b = null;',
        }),
        throwsA(
          isA<CompileFailure>().having(
            (failure) => failure.problems.single.path,
            'path',
            endsWith('/b.dart'),
          ),
        ),
        reason: directive,
      );
    }
    await expectLater(
      loadFiles({
        'main.dart': "part 'part.dart';\nvoid main() {}",
        'part.dart': "part of 'main.dart';\nint b = null;",
      }),
      throwsA(
        isA<CompileFailure>().having(
          (failure) => failure.problems.single.path,
          'path',
          endsWith('/part.dart'),
        ),
      ),
    );
  });

  test('libraries importing each other appear once', () async {
    final program = await loadFiles({
      'main.dart': "import 'a.dart';\nvoid main() => a();",
      'a.dart': "import 'main.dart';\nvoid a() => main();",
    });
    expect(program.libraries, hasLength(2));
    expect(program.main.units.single.path, endsWith('/main.dart'));
  });

  test('missing files are reported', () async {
    await expectLater(
      loadProgram('/no/such/main.dart', sdk: await packagedSdk()),
      failsWith(['main.dart:1:1: File not found.']),
    );
    await expectLater(
      load("import 'missing.dart';\nvoid main() {}"),
      throwsA(
        isA<CompileFailure>().having(
          (failure) => failure.problems.single.line,
          'line',
          1,
        ),
      ),
    );
  });

  test('a part is not a program', () async {
    await expectLater(
      loadFiles({
        'main.dart': "part of 'other.dart';\nvoid main() {}",
        'other.dart': "part 'main.dart';",
      }),
      failsWith(['main.dart:1:1: Not a library that can be compiled.']),
    );
  });

  test(
    'positions are those in the file where constants are compared',
    () async {
      // The analyzer gets another text.
      const text =
          'const a = 0.0 == -0.0, b = 1.0 == (a ? 2.0 : 3.0); int c = "x";\n'
          'const double? q = 1, r = q == 2.0 ? 1 : 2; void main() { d(); }';
      await expectLater(
        load(text),
        failsWith([
          'main.dart:1:60: A value of type \'String\' can\'t be assigned to a '
              'variable of type \'int\'.',
          'main.dart:2:58: Undefined name \'d\'.',
        ]),
      );
    },
  );

  group('programs loaded one after the other', () {
    Future<String> first(Directory directory) async {
      final program = await loadProgram(
        '${directory.path}/main.dart',
        sdk: await packagedSdk(),
      );
      return [
        for (final library in program.libraries)
          for (final unit in library.units) unit.ast.toSource(),
      ].join('|');
    }

    test('share the SDK', () async {
      final [one, two] = [
        for (final text in ['one', 'two'])
          await load("void main() { print('$text'); }"),
      ];
      expect(two.sdk.first.element, same(one.sdk.first.element));
      expect(two.main.element, isNot(one.main.element));
    });

    test('see what changed', () async {
      final directory = writeSources({
        'main.dart': "import 'a.dart'; void main() => f();",
        'a.dart': 'void f() {}',
      });
      void write(String name, String text) =>
          File('${directory.path}/$name').writeAsStringSync(text);
      expect(await first(directory), contains('void f() {}'));
      write('a.dart', 'int f() => 1;');
      expect(await first(directory), contains('int f() => 1;'));
      write('main.dart', "import 'a.dart'; void main() { f(); f(); }");
      expect(await first(directory), contains('{f(); f();}'));
      write('a.dart', 'int f() => wrong;');
      await expectLater(first(directory), throwsA(isA<CompileFailure>()));
      // An error is not kept either.
      write('a.dart', 'int f() => 2;');
      expect(await first(directory), contains('int f() => 2;'));
    });

    test('see files that were missing', () async {
      final directory = writeSources({
        'main.dart': "import 'a.dart'; void main() => f();",
      });
      await expectLater(first(directory), throwsA(isA<CompileFailure>()));
      File('${directory.path}/a.dart').writeAsStringSync('void f() {}');
      expect(await first(directory), contains('void f() {}'));
      // Another program can need one, too.
      final other = writeSources({
        'main.dart': "import 'b.dart'; void main() => g();",
        'b.dart': "export '${directory.path}/c.dart';",
      });
      await expectLater(first(other), throwsA(isA<CompileFailure>()));
      File('${directory.path}/c.dart').writeAsStringSync('void g() {}');
      final third = writeSources({
        'main.dart': "import '${directory.path}/c.dart'; void main() => g();",
      });
      expect(await first(third), contains('void g() {}'));
    });

    test(
      'see a part that becomes a library, and the other way round',
      () async {
        final directory = writeSources({
          'main.dart': "part of 'other.dart'; void main() {}",
        });
        final main = File('${directory.path}/main.dart');
        await expectLater(first(directory), throwsA(isA<CompileFailure>()));
        main.writeAsStringSync('void main() { 1; }');
        expect(await first(directory), contains('{1;}'));
        main.writeAsStringSync("part of 'other.dart';");
        await expectLater(first(directory), throwsA(isA<CompileFailure>()));
      },
    );

    test('see parts that were missing', () async {
      final directory = writeSources({
        'main.dart': "part 'a.dart'; void main() => f();",
      });
      await expectLater(first(directory), throwsA(isA<CompileFailure>()));
      File('${directory.path}/a.dart')
          .writeAsStringSync("part of 'b.dart'; void f() {}");
      File('${directory.path}/b.dart')
          .writeAsStringSync("part 'a.dart'; void main() => f();");
      final program = await loadProgram(
        '${directory.path}/b.dart',
        sdk: await packagedSdk(),
      );
      expect(program.main.units, hasLength(2));
    });

    test('see a part that becomes a program', () async {
      final directory = writeSources({
        'main.dart': "part 'a.dart'; void main() => f();",
        'a.dart': "part of 'main.dart'; void f() {}",
      });
      expect(await first(directory), contains('void f() {}'));
      final part = File('${directory.path}/a.dart')
        ..writeAsStringSync('void main() { 2; }');
      final program = await loadProgram(part.path, sdk: await packagedSdk());
      expect(program.main.units.single.ast.toSource(), contains('{2;}'));
    });

    test('see what was only imported under other conditions', () async {
      final directory = writeSources({
        'main.dart':
            "import 'a.dart' if (dart.library.js_interop) 'b.dart';\n"
            'void main() => f();',
        'a.dart': 'void f() {}',
        'b.dart': 'int f() => 1;',
      });
      expect(await first(directory), contains('void f() {}'));
      File('${directory.path}/b.dart').writeAsStringSync('int f() => 2;');
      final other = writeSources({
        'main.dart': "import '${directory.path}/b.dart'; void main() => f();",
      });
      expect(await first(other), contains('int f() => 2;'));
    });

    test('in packages and outside do not mix', () async {
      final package = writeSources({
        'pubspec.yaml': 'name: a\nenvironment: {sdk: ^3.14.0}\n',
        '.dart_tool/package_config.json':
            '{"configVersion": 2, "packages": '
            '[{"name": "a", "rootUri": "../", "packageUri": "lib/"}]}',
        'lib/a.dart': 'int f() => 1;',
        'main.dart': "import 'package:a/a.dart'; void main() => print(f());",
      });
      expect(await first(package), contains('int f() => 1;'));
      File('${package.path}/lib/a.dart').writeAsStringSync('int f() => 2;');
      expect(await first(package), contains('int f() => 2;'));
      final outside = writeSources({
        'main.dart': "import 'package:a/b.dart'; void main() => print(g());",
      });
      File('${package.path}/lib/b.dart').writeAsStringSync('int g() => 3;');
      await expectLater(first(outside), throwsA(isA<CompileFailure>()));
    });

    test('are the same as alone', () async {
      const source =
          "class A { String toString() => 'a'; }\n"
          "void main() { print([A(), const {'x': 1}]); }";
      Future<List<int>> build(SdkSources sdk) => buildProgram(
        '${writeSources({'main.dart': source}).path}/main.dart',
        sdk,
        const CompileOptions(),
      );
      final files = await packagedSdkFiles();
      final alone = await build(sdkFor(.macosArm64, files));
      final sdk = await packagedSdk();
      await load("import 'dart:io'; void main() { exitCode = 1; }");
      await load('void main() { print(RegExp("a").pattern); }');
      expect(await build(sdk), alone);
      expect(await build(sdk), alone);
    });
  });
}
