import 'dart:convert';

import 'package:dartc/parser.dart';
import 'package:dartc/project.dart';
import 'package:test/test.dart';

PackageConfiguration configuration(List<Object?> packages) =>
    PackageConfiguration.parse(
      jsonEncode({'configVersion': 2, 'packages': packages}),
      uri: Uri.parse('file:///work/app/.dart_tool/package_config.json'),
    );

void main() {
  test('resolves relative roots, exposed roots and package versions', () {
    final config = configuration([
      {
        'name': 'app',
        'rootUri': '../',
        'packageUri': 'lib/',
        'languageVersion': '3.13',
      },
      {'name': 'dep', 'rootUri': '../../dep', 'packageUri': 'source'},
      {
        'name': 'nested',
        'rootUri': '../tools/nested/',
        'packageUri': 'lib/',
        'languageVersion': '3.12',
      },
    ]);
    expect(
      config.resolve(Uri.parse('package:app/src/a.dart')),
      Uri.parse('file:///work/app/lib/src/a.dart'),
    );
    expect(
      config.resolve(Uri.parse('package:dep/a:b.dart')),
      Uri.parse('file:///work/dep/source/a%3Ab.dart'),
    );
    expect(
      config.resolve(Uri.parse('package:app/a%20b.dart')),
      Uri.parse('file:///work/app/lib/a%20b.dart'),
    );
    expect(config.resolve(Uri.parse('package:missing/a.dart')), isNull);
    expect(
      config.resolve(Uri.parse('package:app//elsewhere/a.dart')),
      Uri.parse('file:///elsewhere/a.dart'),
    );
    expect(
      config
          .packageFor(Uri.parse('file:///work/app/test/a.dart'))
          ?.languageVersion,
      const LanguageVersion(3, 13),
    );
    expect(
      config
          .packageFor(Uri.parse('file:///work/app/tools/nested/test/a.dart'))
          ?.name,
      'nested',
    );
    expect(config.packageFor(Uri.parse('package:dep/a.dart'))?.name, 'dep');
    expect(config.packageFor(Uri.parse('memory:main.dart')), isNull);
    expect(
      config.packageFor(Uri.parse('file:///work/application/a.dart')),
      isNull,
    );
    expect(() => config.packages.clear(), throwsUnsupportedError);
  });

  test('defaults packageUri to root and ignores unrelated metadata', () {
    final config = configuration([
      {
        'name': 'valid-name',
        'rootUri': '../',
        'extra': {'data': true},
      },
    ]);
    expect(
      config.resolve(Uri.parse('package:valid-name/a.dart')),
      Uri.parse('file:///work/app/a.dart'),
    );
    expect(config.packages['valid-name']!.languageVersion, isNull);
    expect(
      configuration([
        {'name': 'here', 'rootUri': ''},
      ]).resolve(Uri.parse('package:here/a.dart')),
      Uri.parse('file:///work/app/.dart_tool/a.dart'),
    );
  });

  test('rejects invalid package entries and root conflicts', () {
    for (final entries in <List<Object?>>[
      [null],
      [
        {'name': 'app'},
      ],
      [
        {'name': '', 'rootUri': '../'},
      ],
      [
        {'name': '...', 'rootUri': '../'},
      ],
      [
        {'name': 'a/b', 'rootUri': '../'},
      ],
      [
        {'name': 'a%20b', 'rootUri': '../'},
      ],
      [
        {'name': 'a', 'rootUri': '../', 'packageUri': '/lib/'},
      ],
      [
        {'name': 'a', 'rootUri': '../', 'packageUri': '../../'},
      ],
      [
        {'name': 'a', 'rootUri': '../', 'packageUri': 'file:///elsewhere/'},
      ],
      [
        {'name': 'a', 'rootUri': 'package:app/'},
      ],
      [
        {'name': 'a', 'rootUri': '../#fragment'},
      ],
      [
        {'name': 'a', 'rootUri': '../', 'languageVersion': '03.13'},
      ],
      [
        {'name': 'a', 'rootUri': '../', 'languageVersion': '3.13.0'},
      ],
      [
        {'name': 'a', 'rootUri': '../', 'languageVersion': 3},
      ],
      [
        {'name': 'a', 'rootUri': '../', 'languageVersion': '2147483648.0'},
      ],
      [
        {'name': 'a', 'rootUri': '../'},
        {'name': 'a', 'rootUri': '../../other/'},
      ],
      [
        {'name': 'a', 'rootUri': '../'},
        {'name': 'b', 'rootUri': '../'},
      ],
      [
        {'name': 'a', 'rootUri': '../', 'packageUri': 'lib/'},
        {'name': 'b', 'rootUri': '../lib/nested/'},
      ],
      [
        {'name': 'a', 'rootUri': '../', 'packageUri': 'nested/lib/'},
        {'name': 'b', 'rootUri': '../nested/'},
      ],
    ]) {
      expect(
        () => configuration(entries),
        throwsFormatException,
        reason: '$entries',
      );
    }
    for (final text in [
      'null',
      '{}',
      '{',
      '{"configVersion":2.0,"packages":[]}',
      '{"configVersion":3,"packages":[]}',
    ]) {
      expect(
        () => PackageConfiguration.parse(
          text,
          uri: Uri.parse('file:///config.json'),
        ),
        throwsFormatException,
      );
    }
  });

  test('discovers the nearest configuration without falling back from invalid contents', () async {
    final calls = <Uri>[];
    final files = {
      Uri.parse('memory:/app/.dart_tool/package_config.json'):
          '{"configVersion":2,"packages":[]}',
      Uri.parse('memory:/.dart_tool/package_config.json'): '{',
    };
    Future<PackageConfiguration?> find() => findPackageConfiguration(
      Uri.parse('memory:/app/bin/main.dart'),
      readSource: (uri) {
        calls.add(uri);
        return files[uri];
      },
    );
    expect(await find(), isA<PackageConfiguration>());
    expect(calls, [
      Uri.parse('memory:/app/bin/.dart_tool/package_config.json'),
      Uri.parse('memory:/app/.dart_tool/package_config.json'),
    ]);
    files[Uri.parse('memory:/app/.dart_tool/package_config.json')] = '{';
    await expectLater(find(), throwsFormatException);
    expect(
      await findPackageConfiguration(
        Uri.parse('memory:main.dart'),
        readSource: (_) => null,
      ),
      isNull,
    );
  });
}
