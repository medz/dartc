@Tags(['assets', 'native'])
library;

import 'dart:io';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  test('async functions resume values, errors and cleanup', () async {
    final reference = await Process.run(Platform.resolvedExecutable, [
      'test/compiler/fixtures/async_functions.dart',
    ]);
    final native = await Process.run(
      NativeAssets(Target.host())
          .file('compiler/entry_async_functions')
          .absolute
          .path,
      [],
      includeParentEnvironment: false,
      environment: {'PATH': ''},
    );
    for (final result in [reference, native]) {
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(result.stderr, isEmpty);
      expect(result.stdout, endsWith('42:retained 中文🙂 | \ndone\n'));
    }
    expect(native.stdout, reference.stdout);
  });
  test('uncaught async main errors reach the process boundary', () async {
    final result = await Process.run(
      NativeAssets(Target.host())
          .file('compiler/entry_async_error')
          .absolute
          .path,
      [],
      includeParentEnvironment: false,
      environment: {'PATH': ''},
    );
    expect(result.exitCode, 255);
    expect(result.stdout, isEmpty);
    expect(result.stderr, 'Unhandled Dart exception at native boundary.\n');
  });
}
