@Tags(['assets', 'native'])
library;

import 'dart:io';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  test(
    'Stopwatch preserves lifecycle, clock units and captured method state',
    () async {
      final result = await Process.run(
        NativeAssets(Target.host())
            .file('compiler/entry_stopwatch')
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
      expect(result.stdout, 'stopwatch:ok\n');
    },
  );
}
