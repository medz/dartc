@Tags(['assets', 'native'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  List<List<String>> commands() => [
    [
      Platform.resolvedExecutable,
      File('test/compiler/fixtures/temporary_directories.dart').absolute.path,
    ],
    [
      NativeAssets(Target.host())
          .file('compiler/entry_temporary_directories')
          .absolute
          .path,
    ],
  ];

  test('system temp uses current environment precedence, one trailing slash and overrides', () async {
    for (final (environment, expected) in <(Map<String, String>, String)>[
      ({}, '/tmp'),
      ({'TMP': 'fallback/'}, 'fallback'),
      ({'TMPDIR': '中文///', 'TMP': 'ignored'}, '中文//'),
      ({'TMPDIR': '', 'TMP': 'ignored'}, ''),
      ({'TMPDIR': '/'}, '/'),
      ({'TMPDIR': '\ufeffrelative/'}, '\ufeffrelative'),
    ]) {
      for (final command in commands()) {
        final result = await Process.run(
          command.first,
          [...command.skip(1), 'system'],
          includeParentEnvironment: false,
          environment: environment,
        );
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect(result.stderr, isEmpty);
        expect(result.stdout, '${jsonEncode(expected)}\noverride\n');
      }
    }
  });

  test('temporary directories are unique, privately created and preserve factory overrides', () async {
    for (final command in commands()) {
      final root = (Directory('build/test')..createSync(recursive: true))
          .createTempSync('temporary-directories-')
          .absolute;
      addTearDown(() => root.deleteSync(recursive: true));
      Directory('${root.path}/nested').createSync();
      final result = await Process.run(
        command.first,
        [...command.skip(1), 'create'],
        workingDirectory: root.path,
        includeParentEnvironment: false,
        environment: {'PATH': ''},
      );
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stderr, isEmpty);
      final created = jsonDecode(result.stdout as String) as List;
      expect(created, hasLength(13));
      final names = <String>{};
      for (final List entry in created) {
        final prefix = (entry[0] as String? ?? '').split('\u0000').first;
        final name = entry[1] as String;
        expect(name, startsWith('./$prefix'));
        expect(name.length, greaterThan(2 + prefix.length));
        expect(names.add(name), isTrue);
        final stat = Directory('${root.path}/$name').statSync();
        expect(stat.type, FileSystemEntityType.directory);
        expect(stat.mode & 0x1ff, 0x1c0);
      }
    }
  });

  test(
    'temporary creation preserves argument and filesystem failures',
    () async {
      final outputs = <Object>[];
      for (final command in commands()) {
        final root = (Directory('build/test')..createSync(recursive: true))
            .createTempSync('temporary-errors-')
            .absolute;
        addTearDown(() => root.deleteSync(recursive: true));
        File('${root.path}/ordinary-file').writeAsStringSync('not a directory');
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
        expect(result.stdout, startsWith('argument\n[true,"missing/p-",2]\n'));
        expect(result.stdout, endsWith('true\n'));
        outputs.add(result.stdout);
      }
      expect(outputs[0], outputs[1]);
    },
  );

  test(
    'system temp observes environment changes after a cached Platform snapshot',
    () async {
      for (final command in commands()) {
        final result = await Process.run(
          command.first,
          [...command.skip(1), 'mutation'],
          includeParentEnvironment: false,
          environment: {'TMPDIR': 'before'},
        );
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect(result.stderr, isEmpty);
        expect(result.stdout, 'before|after|before\n');
      }
    },
  );
}
