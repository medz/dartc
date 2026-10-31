import 'dart:convert';

import 'package:dartc/parser.dart';
import 'package:dartc/project.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  test(
    'a part uses its own package default and must agree with its library',
    () async {
      final packages = PackageConfiguration.parse(
        jsonEncode({
          'configVersion': 2,
          'packages': [
            {
              'name': 'app',
              'rootUri': '../',
              'packageUri': 'lib/',
              'languageVersion': '3.13',
            },
            {
              'name': 'other',
              'rootUri': '../../other/',
              'packageUri': 'lib/',
              'languageVersion': '3.12',
            },
          ],
        }),
        uri: uri('.dart_tool/package_config.json'),
      );
      final files = sources({'main.dart': "part 'memory:/other/p.dart';"});
      files[Uri.parse('memory:/other/p.dart')] =
          "part of 'memory:/app/main.dart'; class C;";
      final result = await ProjectLoader(
        packages: packages,
        readSource: (uri) => files[uri],
      ).load(uri('main.dart'));
      expect(
        result.diagnostics.map((d) => d.code),
        containsAll([
          'project.part_language_version',
          'parser.language_feature_disabled',
        ]),
      );
      expect(
        result.libraries[uri('main.dart')]!.parts.single.languageVersion,
        const LanguageVersion(3, 12),
      );
    },
  );

  test(
    'selects the first header override before any language tokens',
    () async {
      for (final header in [
        '// @dart=3.12\n',
        '//\t@dart\t=\t3.12\t\n',
        '// @dart=03.012\n',
        '// @dart=3.12\n// @dart=3.13\n',
        '#!/usr/bin/env dart\n/* header */\n// @dart=3.12\n',
        '\ufeff// @dart=3.12\n',
      ]) {
        final result = await loader(sources({'main.dart': '${header}class C;'}))
            .load(uri('main.dart'));
        final unit = result.libraries[uri('main.dart')]!.unit;
        expect(
          unit.languageVersion,
          const LanguageVersion(3, 12),
          reason: header,
        );
        expect(unit.versionMarker!.text, contains('@dart'));
        expect(
          result.diagnostics.map((d) => d.code),
          contains('parser.language_feature_disabled'),
        );
      }
      for (final header in [
        '/* // @dart=3.12 */\n',
        '/// @dart=3.12\n',
        '// @dart=3.12.0\n',
        '// @dart=3.12 trailing\n',
        'library;\n// @dart=3.12\n',
      ]) {
        final result = await loader(sources({'main.dart': '${header}class C;'}))
            .load(uri('main.dart'));
        expect(result.diagnostics, isEmpty, reason: header);
        expect(
          result.libraries[uri('main.dart')]!.unit.versionOverride,
          isNull,
        );
      }
    },
  );

  test('uses package versions for bin and test files and allows a newer file override', () async {
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
    final files = sources({'bin/main.dart': 'class C;'});
    final projectLoader = ProjectLoader(
      packages: config,
      readSource: (uri) => files[uri],
    );
    var result = await projectLoader.load(uri('bin/main.dart'));
    expect(result.hasErrors, isTrue);
    files[uri('bin/main.dart')] = '// @dart=3.13\nclass C;';
    result = await projectLoader.load(uri('bin/main.dart'));
    expect(result.diagnostics, isEmpty);
  });

  test(
    'diagnoses unsupported overrides rather than falling back to the default',
    () async {
      for (final version in [
        '2.11',
        '9.0',
        '999999999999999999999999999999999.0',
      ]) {
        final result = await loader(
          sources({'main.dart': '// @dart=$version\nvoid main() {}'}),
        ).load(uri('main.dart'));
        expect(
          result.diagnostics.map((d) => d.code),
          contains(
            version.length > 20
                ? 'project.invalid_language_version'
                : 'parser.unsupported_language_version',
          ),
        );
      }
    },
  );
}
