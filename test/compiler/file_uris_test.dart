@Tags(['assets', 'native'])
library;

import 'dart:io';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  for (final mode in ['base', 'paths']) {
    test('file URIs preserve $mode contracts', () async {
      final root = (Directory(
        'build/test',
      )..createSync(recursive: true)).createTempSync('file-uris-').absolute;
      addTearDown(() => root.deleteSync(recursive: true));
      Directory('${root.path}/子目录 #?%').createSync();
      final outputs = <String>[];
      for (final command in [
        [
          Platform.resolvedExecutable,
          File('test/compiler/fixtures/file_uris.dart').absolute.path,
        ],
        [
          NativeAssets(Target.host())
              .file('compiler/entry_file_uris')
              .absolute
              .path,
        ],
      ]) {
        final result = await Process.run(command.first, [
          ...command.skip(1),
          mode,
        ], workingDirectory: root.path);
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect(result.stderr, isEmpty);
        outputs.add(result.stdout as String);
      }
      expect(outputs.last, outputs.first);
      if (mode == 'base') {
        expect(outputs.last, startsWith('[true,true,true,true,true]\n'));
        expect(outputs.last, endsWith('true\n'));
      }
    });
  }
}
