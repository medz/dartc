@Tags(['assets', 'native'])
library;

import 'dart:io';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  test('sync* preserves iterations, cleanup, captures and GC roots', () async {
    final reference = await Process.run(Platform.resolvedExecutable, [
      'test/compiler/fixtures/sync_generators.dart',
    ]);
    final native = await Process.run(
      NativeAssets(Target.host())
          .file('compiler/entry_sync_generators')
          .absolute
          .path,
      [],
      includeParentEnvironment: false,
      environment: {'PATH': ''},
    );
    for (final result in [reference, native]) {
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(result.stderr, isEmpty);
      expect(
        result.stdout,
        endsWith(
          '42:retained 中文🙂:3.25:1234\n42:retained 中文🙂:3.25:1234\ndone\n',
        ),
      );
    }
    expect(native.stdout, reference.stdout);
  });
  test(
    'reentry preserves cleanup and frames release dead reference slots',
    () async {
      final result = await Process.run(
        NativeAssets(Target.host())
            .file('compiler/entry_sync_reentry')
            .absolute
            .path,
        [],
        includeParentEnvironment: false,
        environment: {'PATH': ''},
      );
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(result.stderr, isEmpty);
      expect(result.stdout, '257\nrejected:true:false\nreleased:false\n');
    },
  );
}
