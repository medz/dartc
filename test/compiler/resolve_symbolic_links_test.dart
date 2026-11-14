@Tags(['assets', 'native'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  late Directory root;
  List<List<String>> commands() => [
    [
      Platform.resolvedExecutable,
      File('test/compiler/fixtures/resolve_symbolic_links.dart').absolute.path,
    ],
    [
      NativeAssets(Target.host())
          .file('compiler/entry_resolve_symbolic_links')
          .absolute
          .path,
    ],
  ];

  setUp(() {
    root = (Directory(
      'build/test',
    )..createSync(recursive: true)).createTempSync('symbolic-links-').absolute;
    addTearDown(() => root.deleteSync(recursive: true));
    Directory('${root.path}/real/inner').createSync(recursive: true);
    File('${root.path}/real/中文.txt').writeAsStringSync('target');
    File('${root.path}/real/sibling.txt').writeAsStringSync('sibling');
    for (final (name, target) in [
      ('file-link', 'real/中文.txt'),
      ('chain', 'file-link'),
      ('dir-link', 'real/inner'),
      ('dangling', 'missing'),
      ('loop', 'loop'),
    ]) {
      Link('${root.path}/$name').createSync(target);
    }
  });

  test(
    'file, directory and link paths resolve through real filesystem links',
    () async {
      final base = root.resolveSymbolicLinksSync();
      final expected = [
        base,
        '$base/real',
        '$base/real/中文.txt',
        '$base/real/中文.txt',
        '$base/real/sibling.txt',
        '$base/real/中文.txt',
        '$base/real/中文.txt',
        '$base/real/中文.txt',
      ];
      for (final command in commands()) {
        final result = await Process.run(
          command.first,
          [...command.skip(1), 'paths'],
          workingDirectory: root.path,
          includeParentEnvironment: false,
          environment: {'PATH': ''},
        );
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect(result.stderr, isEmpty);
        expect(jsonDecode(result.stdout as String), [
          ...expected,
          ...expected,
          ...expected,
        ]);
      }
    },
  );

  test(
    'invalid paths preserve the SDK filesystem errors and original names',
    () async {
      final outputs = <Object>[];
      for (final command in commands()) {
        final result = await Process.run(
          command.first,
          [...command.skip(1), 'failures'],
          workingDirectory: root.path,
          includeParentEnvironment: false,
          environment: {'PATH': ''},
        );
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect(result.stderr, isEmpty);
        final failures = jsonDecode(result.stdout as String) as List;
        expect(failures, hasLength(6));
        expect(failures.map((dynamic failure) => failure[0]), [
          '',
          'missing',
          'dangling',
          'loop',
          'real/中文.txt/child',
          'x' * 300,
        ]);
        expect(failures.take(3).map((dynamic failure) => failure[1]), [
          2,
          2,
          2,
        ]);
        expect(failures[3][1], anyOf(40, 62));
        expect(failures[4][1], 20);
        for (final List failure in failures) {
          expect(failure[1], greaterThan(0));
          expect(failure.skip(2), [true, false]);
        }
        outputs.add(result.stdout);
      }
      expect(outputs[0], outputs[1]);
    },
  );
}
