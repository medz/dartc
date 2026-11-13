@Tags(['assets', 'native'])
library;

import 'dart:io';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  test(
    'dynamic libraries preserve typed calls, ownership and loader failures',
    () async {
      final native = await Process.run(
        NativeAssets(Target.host())
            .file('compiler/entry_dynamic_libraries')
            .path,
        [],
      );
      expect(native.exitCode, 0, reason: '${native.stdout}\n${native.stderr}');
      final sdk = await Process.run(Platform.resolvedExecutable, [
        'test/compiler/fixtures/dynamic_libraries_sdk.dart',
      ]);
      expect(sdk.exitCode, 0, reason: '${sdk.stdout}\n${sdk.stderr}');
      expect(native.stdout, sdk.stdout);
    },
  );
}
