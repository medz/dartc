@Tags(['assets', 'native'])
library;

import 'dart:io';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  final assets = NativeAssets(Target.host());
  test('print preserves output and ignores stdout descriptor errors', () async {
    for (final command in [
      [assets.file('compiler/entry_console').absolute.path],
      [
        Platform.resolvedExecutable,
        File('test/compiler/fixtures/console.dart').absolute.path,
      ],
    ]) {
      final normal = await Process.run(command.first, command.skip(1).toList());
      expect(normal.exitCode, 0, reason: '${normal.stderr}');
      expect(
        normal.stdout,
        'Hello, Dart!\nNUL:\u0000 中文🙂\n\ufffdx\ufffd\nnull\n42\n43\n',
      );
      expect(normal.stderr, isEmpty);

      final failed = await Process.run(Platform.resolvedExecutable, [
        File('test/compiler/fixtures/raw_process_client.dart').absolute.path,
        'read-only-stdout',
        ...command,
      ]);
      expect(failed.exitCode, 0, reason: '${failed.stderr}');
      expect(failed.stdout, isEmpty);
      expect(failed.stderr, isEmpty);
    }
  });
}
