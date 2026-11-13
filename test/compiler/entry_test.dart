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

  test('main receives target arguments across defaults, suspension and collection', () async {
    for (final arguments in <List<String>>[
      [],
      ['', 'space here', '--flag=value', '中文', '🙂', 'line\nnext', '\ufeffBOM'],
      List.generate(300, (i) => 'argument $i'),
    ]) {
      for (final name in [
        'arguments',
        'arguments_async',
        'arguments_optional',
      ]) {
        final result = await Process.run(
          assets.file('compiler/entry_$name').absolute.path,
          arguments,
          includeParentEnvironment: false,
          environment: {'PATH': ''},
        );
        expect(result.exitCode, 0, reason: '$name: ${result.stderr}');
        expect(result.stderr, isEmpty);
        expect(
          result.stdout,
          '${arguments.length}\n${[for (var i = 0; i < arguments.length; i++) '$i:${arguments[i].length}:${arguments[i]}\n'].join()}',
        );
      }
    }
  });

  test('named and generic mains keep their default invocation', () async {
    for (final (name, expected) in [
      ('named', '73\n'),
      ('generic', 'generic\n'),
    ]) {
      final result = await Process.run(
        assets.file('compiler/entry_arguments_$name').absolute.path,
        ['ignored'],
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout, expected);
      expect(result.stderr, isEmpty);
    }
  });

  test('malformed UTF-8 process arguments fail before main', () async {
    final result = await Process.run(Platform.resolvedExecutable, [
      File('test/compiler/fixtures/entry/raw_arguments_client.dart')
          .absolute
          .path,
      assets.file('compiler/entry_arguments').absolute.path,
    ]);
    expect(result.exitCode, 255);
    expect(result.stdout, isEmpty);
    expect(
      result.stderr,
      contains('Unhandled Dart exception at native boundary.'),
    );
  });

  if (Platform.isLinux) {
    test('dynamic process loader preserves command-line arguments', () async {
      final result = await Process.run(
        assets.file('compiler/entry_arguments_dynamic').absolute.path,
        ['entry', '🙂'],
        includeParentEnvironment: false,
        environment: {'PATH': ''},
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout, '2\n0:5:entry\n1:2:🙂\n');
      expect(result.stderr, isEmpty);
    });

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

  test('missing entries and unused static errors fail compilation', () async {
    final compiler = Compiler(Target.host());
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
  });
}
