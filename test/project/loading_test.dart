import 'dart:async';

import 'dart:convert';

import 'package:dartc/ast.dart';
import 'package:dartc/parser.dart';
import 'package:dartc/project.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  test(
    'an earlier provider error propagates while a later part is pending',
    () async {
      final entry = uri('main.dart');
      final wait = Completer<String?>(), first = Completer<String?>();
      final files = sources({
        'main.dart':
            "part 'a.dart'; part 'b.dart'; part 'c.dart'; part 'd.dart';",
        'c.dart': "part of 'main.dart';",
        'd.dart': "part of 'main.dart';",
      });
      final error = StateError('first part failed');
      final loader = ProjectLoader(
        readSource: (u) {
          if (u == uri('a.dart')) return first.future;
          if (u == uri('b.dart')) return wait.future;
          return files[u];
        },
      );
      final load = loader.load(entry);
      final check = expectLater(load, throwsA(same(error)));
      await Future<void>.delayed(Duration.zero);
      first.completeError(error);
      try {
        await check.timeout(const Duration(seconds: 5));
      } finally {
        wait.complete("part of 'main.dart';");
      }
    },
  );

  test('keeps part order when reads complete in reverse order', () async {
    final names = ['a', 'b', 'c', 'd'];
    final gates = {for (final n in names) uri('$n.dart'): Completer<String?>()};
    final allStarted = Completer<void>();
    final requested = <Uri>{};
    final loader = ProjectLoader(
      readSource: (u) {
        if (u == uri('main.dart')) {
          return names.map((n) => "part '$n.dart';").join();
        }
        if (u == uri('dart:core')) return '';
        if (!requested.add(u)) throw StateError('Duplicate read for $u');
        if (requested.length == gates.length) allStarted.complete();
        return gates[u]!.future;
      },
    );
    final future = loader.load(uri('main.dart'));
    await allStarted.future;
    for (final n in names.reversed) {
      gates[uri('$n.dart')]!.complete(
        n == 'b' || n == 'c' ? null : "part of 'main.dart';",
      );
    }
    final project = await future;
    expect(
      project.libraries[uri('main.dart')]!.parts.map((p) => p.source.uri),
      [uri('a.dart'), uri('d.dart')],
    );
    expect(project.diagnostics.map((d) => d.span!.text), [
      "'b.dart'",
      "'c.dart'",
    ]);
  });

  test(
    'an undefined conditional environment value is the empty string',
    () async {
      final result = await loader(
        sources({
          'main.dart':
              "import 'missing.dart' if (absent == '') 'selected.dart';",
          'selected.dart': '',
        }),
      ).load(uri('main.dart'));
      expect(result.diagnostics, isEmpty);
      expect(result.libraries, contains(uri('selected.dart')));
    },
  );

  test('loads a complete graph with ordered parts, cycles, exports and shared dependencies', () async {
    final files = sources({
      'main.dart': "library app; import 'a.dart' as a show A; export 'b.dart' hide B; part 'part.dart'; void main() {}",
      'a.dart': "import 'main.dart'; import 'b.dart'; class A {}",
      'b.dart': "export 'a.dart'; class B {}",
      'part.dart': 'part of app; int value = 1;',
    });
    final reads = <Uri, int>{};
    final result = await ProjectLoader(
      readSource: (uri) {
        reads.update(uri, (n) => n + 1, ifAbsent: () => 1);
        return files[uri];
      },
    ).load(uri('main.dart'));
    expect(result.diagnostics, isEmpty);
    expect(result.libraries.keys.toSet(), {
      uri('main.dart'),
      uri('a.dart'),
      uri('b.dart'),
      uri('dart:core'),
    });
    expect(reads.values, everyElement(1));
    final main = result.libraries[uri('main.dart')]!;
    expect(main.parts.single.source.uri, uri('part.dart'));
    expect(main.dependencies.map((d) => d.uri), [
      uri('a.dart'),
      uri('b.dart'),
      uri('dart:core'),
    ]);
    expect(
      (main.dependencies.first.directive as ImportDirective).prefix!.text,
      'a',
    );
    expect(main.dependencies[1].isExport, isTrue);
    expect(main.dependencies.last.isImplicit, isTrue);
    expect(() => result.libraries.clear(), throwsUnsupportedError);
    expect(() => main.parts.clear(), throwsUnsupportedError);
    expect(() => result.diagnostics.clear(), throwsUnsupportedError);
  });

  test(
    'selects the first matching condition and reads only selected libraries',
    () async {
      final files = sources({
        'main.dart': "import 'missing.dart' if (enabled) 'a.dart' if (mode == 'native') 'missing-too.dart'; export 'b.dart' if (absent) 'unused.dart';",
        'a.dart': '',
        'b.dart': '',
      });
      final environment = {'enabled': 'true', 'mode': 'native'};
      final projectLoader = loader(files, environment: environment);
      environment['enabled'] = 'false';
      final result = await projectLoader.load(uri('main.dart'));
      expect(result.diagnostics, isEmpty);
      expect(result.libraries.keys.toSet(), {
        uri('main.dart'),
        uri('a.dart'),
        uri('b.dart'),
        uri('dart:core'),
      });
    },
  );

  test(
    'explicit core imports suppress the implicit import, exports do not',
    () async {
      final files = sources({'main.dart': "import 'dart:core' as core;"});
      final projectLoader = loader(files);
      var result = await projectLoader.load(uri('main.dart'));
      expect(
        result.libraries[uri('main.dart')]!.dependencies.single.isImplicit,
        isFalse,
      );
      files[uri('main.dart')] = "export 'dart:core';";
      result = await projectLoader.load(uri('main.dart'));
      expect(result.libraries[uri('main.dart')]!.dependencies, hasLength(2));
      expect(result.libraries[uri('dart:core')]!.dependencies, isEmpty);
    },
  );

  test(
    'decodes raw, adjacent, escaped and multiline directive strings',
    () async {
      final files = sources({
        'main.dart': "import r'a' '.dart'; import '\\u0062\\x2edart'; import '''  \r\nc.dart''';",
        'a.dart': '',
        'b.dart': '',
        'c.dart': '',
      });
      final result = await loader(files).load(uri('main.dart'));
      expect(result.diagnostics, isEmpty);
      expect(result.libraries, hasLength(5));
    },
  );

  test('recovers from malformed directive strings without losing valid dependencies', () async {
    for (final directive in [
      r"import '\x-1';",
      r"import '\u{-1}';",
      r"import '\u{110000}';",
      r"import '\u{}';",
      r"import '$value.dart';",
      "import ;",
    ]) {
      final result = await loader(
        sources({
          'main.dart': "$directive export 'good.dart';",
          'good.dart': '',
        }),
      ).load(uri('main.dart'));
      expect(result.hasErrors, isTrue, reason: directive);
      expect(result.libraries, contains(uri('good.dart')), reason: directive);
    }
  });

  test(
    'uses package source locations while retaining package library identity',
    () async {
      final config = PackageConfiguration.parse(
        jsonEncode({
          'configVersion': 2,
          'packages': [
            {
              'name': 'app',
              'rootUri': '../',
              'packageUri': 'lib/',
              'languageVersion': '3.12',
            },
          ],
        }),
        uri: uri('.dart_tool/package_config.json'),
      );
      final files = sources({
        'main.dart': "import 'package:app/a.dart'; import 'lib/a.dart';",
        'lib/a.dart': "import 'b.dart';",
        'lib/b.dart': '',
      });
      final reads = <Uri, int>{};
      final loader = ProjectLoader(
        packages: config,
        readSource: (uri) {
          reads.update(uri, (n) => n + 1, ifAbsent: () => 1);
          return files[uri];
        },
      );
      final result = await loader.load(uri('main.dart'));
      expect(result.diagnostics, isEmpty);
      expect(result.libraries, contains(Uri.parse('package:app/b.dart')));
      expect(result.libraries, contains(uri('lib/b.dart')));
      expect(reads[uri('lib/a.dart')], 1);
      final unit = result.libraries[Uri.parse('package:app/a.dart')]!.unit;
      expect(unit.languageVersion, const LanguageVersion(3, 12));
      expect(unit.source.uri, Uri.parse('package:app/a.dart'));
      final logical = unit.source.uri, location = uri('lib/a.dart');
      expect(unit.location, location);
      var previous = result;
      for (final changed in [logical, location]) {
        reads.clear();
        files[location] = 'class C {} // $changed';
        final next = await loader.update(previous, changedSources: [changed]);
        expect(reads, {location: 1});
        for (final identity in [logical, location]) {
          final updated = next.libraries[identity]!.unit;
          expect(updated.source.text, files[location]);
          expect(updated.tree.source.uri, identity);
          expect(updated, isNot(same(previous.libraries[identity]!.unit)));
        }
        previous = next;
      }
    },
  );

  test('reports missing, failed and malformed sources without losing other libraries', () async {
    final files = sources({
      'main.dart':
          "import 'missing.dart'; export 'good.dart'; import 'bad.dart?query';",
      'good.dart': 'void f() {',
    });
    final result = await loader(files).load(uri('main.dart'));
    expect(result.hasErrors, isTrue);
    expect(result.libraries, contains(uri('good.dart')));
    expect(
      result.diagnostics.map((d) => d.code),
      containsAll(['project.source_not_found', 'project.invalid_uri']),
    );
    final failed = await ProjectLoader(
      readSource: (_) => throw const FormatException('read failure'),
    ).load(uri('main.dart'));
    expect(failed.diagnostics.single.code, 'project.source_read_failed');
    await expectLater(
      ProjectLoader(readSource: (_) => throw StateError('bug'))
          .load(uri('main.dart')),
      throwsStateError,
    );
  });
}
