@Tags(['assets', 'native'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  for (final mode in [
    'roundtrip',
    'failures',
    'deleted',
    if (Platform.isLinux) 'raw',
  ]) {
    test('current directory preserves $mode behavior', () async {
      final results = <ProcessResult>[];
      for (final command in [
        // The fixed SDK aborts in Dart_NewStringFromUTF8 for a raw invalid name.
        if (mode != 'raw')
          [
            Platform.resolvedExecutable,
            File('test/compiler/fixtures/working_directory.dart').absolute.path,
          ],
        [
          NativeAssets(Target.host())
              .file('compiler/entry_working_directory')
              .absolute
              .path,
        ],
      ]) {
        final root = (Directory('build/test')..createSync(recursive: true))
            .createTempSync('working-directory-')
            .absolute;
        addTearDown(() => root.deleteSync(recursive: true));
        Directory('${root.path}/中文🙂 #?%/nested').createSync(recursive: true);
        Directory('${root.path}/deleted').createSync();
        File('${root.path}/ordinary-file').writeAsStringSync('not a directory');
        if (mode == 'raw') {
          Directory.fromRawPath(
            Uint8List.fromList([...utf8.encode('${root.path}/'), 0xff, 120]),
          ).createSync();
        }
        final result = await Process.run(
          command.first,
          [...command.skip(1), mode],
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
        results.add(result);
      }
      if (mode != 'raw') {
        expect(results.last.stdout, results.first.stdout);
      }
      expect(results.last.stdout, endsWith('$mode:ok\n'));
      if (mode == 'failures') {
        expect(
          results.last.stdout,
          startsWith('[true,"",2,true]\n[true,"missing",2,true]\n'),
        );
        expect(
          results.last.stdout,
          contains('"ordinary-file",20,true]\nargument\nargument\n'),
        );
      }
    });
  }
}
