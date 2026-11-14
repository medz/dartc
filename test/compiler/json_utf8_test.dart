@Tags(['assets', 'native'])
library;

import 'dart:io';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  test(
    'JSON UTF-8 encoding preserves chunks, callbacks, errors and streams',
    () async {
      final result = await Process.run(
        NativeAssets(Target.host())
            .file('compiler/entry_json_utf8')
            .absolute
            .path,
        [],
        includeParentEnvironment: false,
        environment: {'PATH': ''},
      );
      expect(
        result.exitCode,
        0,
        reason: result.stdout.toString() + result.stderr.toString(),
      );
      expect(result.stderr, isEmpty);
      expect(result.stdout, 'json_utf8:ok\n');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
