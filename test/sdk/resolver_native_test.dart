@Tags(['assets', 'native'])
library;

import 'dart:io';

import 'package:dartc/compiler.dart';
import 'package:dartc/sdk.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  final assets = NativeAssets(Target.host());
  final cache = Directory('build/test/sdk/cache').absolute;
  test(
    'a standalone process uses verified sources without a Dart command',
    () async {
      final result = await Process.run(
        assets.file('sdk/resolve').path,
        [cache.path],
        environment: {'PATH': ''},
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(
        (result.stdout as String).trim(),
        Directory.fromUri(cache.uri.resolve('${DartSdk.sourceRevision}/'))
            .resolveSymbolicLinksSync(),
      );
    },
  );
  test('an SDK host precedes PATH and the cache', () async {
    final result = await Process.run(
      Platform.resolvedExecutable,
      ['test/sdk/fixtures/resolve.dart', 'test/compiler/fixtures'],
      environment: {'PATH': ''},
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect((result.stdout as String).trim(), DartSdk.current().directory.path);
  });
  test('PATH and explicit commands work in a standalone process', () async {
    for (final source in [null, 'dart', Platform.resolvedExecutable]) {
      final result = await Process.run(
        assets.file('sdk/resolve').path,
        ['test/compiler/fixtures', ?source],
        environment: {'PATH': File(Platform.resolvedExecutable).parent.path},
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(
        (result.stdout as String).trim(),
        DartSdk.current().directory.path,
      );
    }
  });
  test('explicit errors do not use a valid source cache', () async {
    final result = await Process.run(
      assets.file('sdk/resolve').path,
      [cache.path, 'test/compiler/fixtures'],
      environment: {'PATH': ''},
    );
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('Missing SDK file:'));
  });
  test(
    'the original cached library sources produce the same native object',
    () async {
      final sdk = DartSdk.at(
        Directory.fromUri(cache.uri.resolve('${DartSdk.sourceRevision}/')).path,
      );
      final output = await Compiler(
        Target.host(),
        sdk: sdk,
      ).compile(['test/compiler/fixtures/arithmetic.dart']);
      expect(
        output.bytes,
        assets.file('compiler/arithmetic.o').readAsBytesSync(),
      );
    },
  );
}
