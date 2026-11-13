@Tags(['assets', 'native'])
library;

import 'dart:io';

import 'package:dartc/compiler.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  final assets = NativeAssets(Target.host());
  test(
    'process entries return zero and execute the selected library main',
    () async {
      for (final (name, status) in [
        ('return', 0),
        ('void', 0),
        ('status', 47),
        ('exported', 47),
        ('math', 73),
        if (Platform.isLinux) ('dynamic', 0),
      ]) {
        final file = assets.file('compiler/entry_$name');
        expect(file.statSync().mode & 0x40, isNot(0));
        final result = await Process.run(
          file.absolute.path,
          [],
          includeParentEnvironment: false,
          environment: {'PATH': ''},
        );
        expect(
          result.exitCode,
          status,
          reason: '$name: ${result.stdout}${result.stderr}',
        );
        expect(result.stdout, isEmpty);
        expect(result.stderr, isEmpty);
      }
    },
  );

  if (Platform.isLinux) {
    test(
      'dynamic executable rejects unavailable dependencies before main',
      () async {
        final result = await Process.run(
          assets.file('compiler/entry_missing').absolute.path,
          [],
          includeParentEnvironment: false,
          environment: {'PATH': ''},
        );
        expect(result.exitCode, isNot(0));
        expect(result.stdout, isEmpty);
        expect(result.stderr, contains('libdartc_missing_dependency.so'));
      },
    );
  }

  test(
    'unsupported entries and unused static errors fail compilation',
    () async {
      final compiler = Compiler(Target.host());
      await expectLater(
        compiler.compile([
          'test/compiler/fixtures/entry/arguments.dart',
        ], output: const .executable()),
        throwsUnsupportedError,
      );
      await expectLater(
        compiler.compile([
          'test/compiler/fixtures/arithmetic.dart',
        ], output: const .executable()),
        throwsArgumentError,
      );
      await expectLater(
        compiler.compile([
          'test/compiler/fixtures/invalid_dependency.dart',
        ], output: const .executable()),
        throwsFormatException,
      );
    },
  );
}
