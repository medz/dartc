import 'package:dartc/project.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  test(
    'loads large part bodies and leaves the unselected library unread',
    () async {
      final names = ['a', 'b', 'c', 'd'];
      final text = 'x' * (256 * 1024);
      final files = sources({
        'main.dart':
            "import 'unused.dart' if (enabled) 'chosen.dart';"
            "${names.map((n) => "part '$n.dart';").join()}",
        'chosen.dart': '',
        for (final n in names)
          '$n.dart': "part of 'main.dart';\n// $text\nint $n() => 42;",
      });
      final reads = <Uri>{};
      final projectLoader = ProjectLoader(
        environment: {'enabled': 'true'},
        readSource: (u) {
          if (!reads.add(u)) throw StateError('Duplicate read for $u');
          return files[u];
        },
      );
      final project = await projectLoader.load(uri('main.dart'));
      expect(project.diagnostics, isEmpty);
      expect(reads, unorderedEquals(files.keys));
      final parts = project.libraries[uri('main.dart')]!.parts;
      expect(parts.map((p) => p.node.members.last.text), [
        for (final n in names) 'int $n() => 42;',
      ]);
    },
  );

  test('a deleted part does not change how later parts are matched', () async {
    final main = uri('main.dart'), first = uri('a.dart'), last = uri('b.dart');
    final files = sources({
      'main.dart': "part 'a.dart'; part 'b.dart';",
      'a.dart': "part of 'main.dart';",
      'b.dart': "part of 'main.dart';",
    });
    final projectLoader = loader(files);
    final initial = await projectLoader.load(main);
    expect(initial.diagnostics, isEmpty);
    files.remove(first);
    files[last] = "part of 'other.dart';";
    final next = await projectLoader.update(
      initial,
      changedSources: [first, last],
    );
    expect(next.libraries[main]!.parts.single.source.uri, last);
    expect(next.diagnostics.map((d) => (d.code, d.span!.source.uri)), [
      ('project.source_not_found', main),
      ('project.part_of_mismatch', last),
    ]);
    expect(next.diagnostics.last.notes.single.span.text, "'b.dart'");
    expect(initial.libraries[main]!.parts.map((p) => p.source.uri), [
      first,
      last,
    ]);
  });

  test(
    'loads misplaced directives and validates directives in recovered parts',
    () async {
      final result = await loader(
        sources({
          'main.dart': "class Main {} import 'dep.dart'; part 'p.dart';",
          'dep.dart': '',
          'p.dart': "class P {} part of 'main.dart'; import 'bad.dart';",
        }),
      ).load(uri('main.dart'));
      expect(result.libraries, contains(uri('dep.dart')));
      expect(
        result.libraries[uri('main.dart')]!.parts.single.source.uri,
        uri('p.dart'),
      );
      final errors = result.diagnostics.where(
        (d) => d.code.startsWith('project.'),
      );
      expect(errors.map((d) => (d.code, d.span!.text)), [
        ('project.directive_in_part', "import 'bad.dart';"),
      ]);
    },
  );

  test('checks part ownership by URI and library name', () async {
    for (final part in ["part of 'main.dart';", 'part of app.library;']) {
      final result = await loader(
        sources({
          'main.dart': "library app.library; part 'p.dart';",
          'p.dart': part,
        }),
      ).load(uri('main.dart'));
      expect(result.diagnostics, isEmpty, reason: part);
    }
    for (final (main, part, code) in [
      ("part 'p.dart';", '', 'missing_part_of'),
      ("part 'p.dart';", "part of 'other.dart';", 'part_of_mismatch'),
      ("library app; part 'p.dart';", 'part of other;', 'part_of_mismatch'),
      (
        "part 'p.dart'; part 'p.dart';",
        "part of 'main.dart';",
        'duplicate_part',
      ),
      (
        "part 'p.dart';",
        "part of 'main.dart'; import 'x.dart';",
        'directive_in_part',
      ),
      ("import 'p.dart';", "part of 'main.dart';", 'expected_library'),
    ]) {
      final result = await loader(sources({'main.dart': main, 'p.dart': part}))
          .load(uri('main.dart'));
      expect(
        result.diagnostics.map((d) => d.code),
        contains('project.$code'),
        reason: '$main $part',
      );
      expect(result.hasErrors, isTrue);
    }
  });

  test(
    'reports a part included by two libraries with both source locations',
    () async {
      final result = await loader(
        sources({
          'main.dart': "library shared; import 'other.dart'; part 'p.dart';",
          'other.dart': "library shared; part 'p.dart';",
          'p.dart': 'part of shared;',
        }),
      ).load(uri('main.dart'));
      final error = result.diagnostics.singleWhere(
        (d) => d.code == 'project.shared_part',
      );
      expect(error.span!.source.uri, uri('other.dart'));
      expect(error.notes.single.span.source.uri, uri('main.dart'));
    },
  );

  test('requires equal explicit language overrides even when effective versions match', () async {
    for (final (libraryVersion, partVersion, valid) in [
      ('', '', true),
      ('// @dart=3.12\n', '// @dart=3.12\n', true),
      ('// @dart=3.12\n', '', false),
      ('', '// @dart=3.13\n', false),
      ('// @dart=3.12\n', '// @dart=3.13\n', false),
    ]) {
      final result = await loader(
        sources({
          'main.dart': "$libraryVersion part 'p.dart';",
          'p.dart': "$partVersion part of 'main.dart';",
        }),
      ).load(uri('main.dart'));
      expect(
        result.diagnostics
            .where((d) => d.code == 'project.part_language_version')
            .isEmpty,
        valid,
      );
    }
  });
}
