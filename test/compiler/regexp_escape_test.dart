@Tags(['assets', 'native'])
library;

import 'dart:io';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  test(
    'RegExp.escape preserves literal UTF-16 data and function contracts',
    () async {
      final result = await Process.run(
        NativeAssets(Target.host())
            .file('compiler/entry_regexp_escape')
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
      expect(result.stdout, 'regexp_escape:ok\n');
    },
  );
}
