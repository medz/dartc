@Tags(['assets', 'native'])
library;

import 'dart:io';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  test(
    'SDK streams and async* preserve subscriptions, cleanup and GC roots',
    () async {
      final reference = await Process.run(Platform.resolvedExecutable, [
        'test/compiler/fixtures/async_generators.dart',
      ]);
      final native = await Process.run(
        NativeAssets(Target.host())
            .file('compiler/entry_async_generators')
            .absolute
            .path,
        [],
        includeParentEnvironment: false,
        environment: {'PATH': ''},
      );
      for (final result in [reference, native]) {
        expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
        expect(result.stderr, isEmpty);
        expect(result.stdout, endsWith('done\n'));
        expect(result.stdout, contains('42:retained 中文🙂:3.25:1234\n'));
      }
      expect(native.stdout, reference.stdout);
    },
  );
  test('a failed delegate listen allows later yields and delegation', () async {
    final result = await Process.run(
      NativeAssets(Target.host())
          .file('compiler/entry_async_generator_recovery')
          .absolute
          .path,
      [],
      includeParentEnvironment: false,
      environment: {'PATH': ''},
    );
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    expect(result.stderr, isEmpty);
    expect(result.stdout, '[9, 10, 11, 12]\ndone\n');
  });
}
