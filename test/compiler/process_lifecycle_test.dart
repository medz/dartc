@Tags(['assets', 'native'])
library;

import 'dart:io';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  final assets = NativeAssets(Target.host());
  final executable = assets.file('compiler/entry_process_lifecycle').path;
  test('setting status alone retains the exit hook and its state', () async {
    final result = await Process.run(
      assets.file('compiler/entry_process_status_only').path,
      [],
    );
    expect(result.exitCode, 42, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, isEmpty);
    expect(result.stderr, isEmpty);
  });
  for (final (mode, status) in [
    ('status', 2),
    ('events', 4),
    ('immediate', 7),
    ('override', 5),
    ('sleep', 0),
  ]) {
    test('$mode preserves process lifecycle and SDK effects', () async {
      final native = await Process.run(executable, [mode]);
      final sdk = await Process.run(Platform.resolvedExecutable, [
        'test/compiler/fixtures/process_lifecycle.dart',
        mode,
      ]);
      expect(
        native.exitCode,
        status,
        reason: '${native.stdout}\n${native.stderr}',
      );
      expect(sdk.exitCode, status, reason: '${sdk.stdout}\n${sdk.stderr}');
      expect(native.stdout, sdk.stdout);
      expect(native.stderr, isEmpty);
    });
  }
  test('unhandled errors override the requested normal status', () async {
    final result = await Process.run(executable, ['unhandled']);
    expect(result.exitCode, isNot(anyOf(0, 27)));
    expect(result.stderr, isNotEmpty);
  });
}
