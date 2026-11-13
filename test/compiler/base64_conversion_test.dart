@Tags(['assets', 'native'])
library;

import 'dart:io';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  test(
    'Base64 preserves vectors, chunk state, validation and sink lifetime',
    () async {
      final result = await Process.run(
        NativeAssets(Target.host())
            .file('compiler/entry_base64_conversion')
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
      expect(result.stdout, 'base64:ok\n');
    },
  );
}
