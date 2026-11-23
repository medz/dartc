import 'dart:io';

import 'package:dartc/driver.dart';
import 'package:dartc/source.dart';
import 'package:test/test.dart';

import '../support/new_compiler.dart';

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

  test('disabling ignore comments changes nothing else', () async {
    const text =
        '// ignore: unused_local_variable\n'
        'void main() { var s = "// ignore: x"; } /* ignore */ // é ignore';
    final program = await load(text);
    final changed = program.main.units.single.ast.toSource();
    expect(changed, contains('"// ignore: x"'));
    expect(program.main.units.single.ast.end, text.length);
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
}
