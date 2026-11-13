@Tags(['assets', 'native'])
library;

import 'dart:io';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  test('Random preserves seeded streams and OS entropy sampling', () async {
    final result = await Process.run(
      NativeAssets(Target.host())
          .file('compiler/entry_math_random')
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
    expect(result.stdout, 'random:ok\n');
  });
  if (Target.host() == const Target(.linux, .arm64)) {
    for (final (source, scenario) in [
      ('random_unavailable', 'at construction'),
      ('random_source_lost', 'after construction'),
    ]) {
      test('secure entropy failure $scenario cannot use a weak seed', () async {
        final result = await Process.run(
          NativeAssets(Target.host())
              .file('compiler/entry_$source')
              .absolute
              .path,
          [],
        );
        expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
        expect(result.stderr, isEmpty);
        expect(result.stdout, 'entropy:unavailable\n');
      });
    }
  }
}
