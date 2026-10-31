import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
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
