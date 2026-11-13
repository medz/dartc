@Tags(['assets', 'native'])
library;

import 'dart:io';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  test(
    'allocator calls retain target sizes, dispatch, effects and ownership',
    () async {
      final native = await Process.run(
        NativeAssets(Target.host()).file('compiler/entry_allocators').path,
        [],
      );
      expect(native.exitCode, 0, reason: '${native.stdout}\n${native.stderr}');
      final sdk = await Process.run(Platform.resolvedExecutable, [
        'test/compiler/fixtures/allocators.dart',
      ]);
      expect(sdk.exitCode, 0, reason: '${sdk.stdout}\n${sdk.stderr}');
      expect(native.stdout, sdk.stdout);
    },
  );
}
