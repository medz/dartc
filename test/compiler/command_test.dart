@Tags(['assets', 'native'])
library;

import 'dart:io';

import 'package:dartc/src/compiler/cli/command.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';
import 'fixtures/environment_config.dart';

void main() {
  test(
    'CLI preserves compilation declarations and rejects malformed input',
    () async {
      final errors = StringBuffer();
      final command = CompilerCommand(StringBuffer(), errors);
      final directory = (Directory(
        'build/test',
      )..createSync(recursive: true)).createTempSync('cli-environment-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File.fromUri(directory.uri.resolve('program'))
        ..writeAsStringSync('existing output');
      const source = 'test/compiler/fixtures/environment.dart';
      for (final declaration in ['-Dbroken', '--define=', '-D=value', '-D']) {
        expect(await command.run([source, '-o', file.path, declaration]), 64);
        expect(file.readAsStringSync(), 'existing output');
      }
      for (final name in [
        'dart.library.io',
        'dart.library.js_interop',
        'dart.library.unknown',
      ]) {
        errors.clear();
        expect(
          await command.run([source, '-o', file.path, '-D$name=false']),
          1,
        );
        expect(errors.toString(), contains('Reserved SDK declaration'));
        expect(file.readAsStringSync(), 'existing output');
      }
      expect(
        await command.run([
          source,
          '-o',
          file.path,
          '--kind',
          'exe',
          '-Dtext=replaced',
          '--define',
          'text=${environmentDefinitions['text']}',
          '--define=number=0x2a',
          '-D',
          'enabled=false',
          for (final MapEntry(:key, :value) in environmentDefinitions.entries)
            if (!{'text', 'number', 'enabled'}.contains(key)) '-D$key=$value',
        ]),
        0,
        reason: errors.toString(),
      );
      final result = await Process.run(file.path, []);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final sdk = await Process.run(Platform.resolvedExecutable, [
        for (final MapEntry(:key, :value) in environmentDefinitions.entries)
          '-D$key=$value',
        source,
      ]);
      expect(sdk.exitCode, 0, reason: '${sdk.stdout}\n${sdk.stderr}');
      expect(
        result.stdout,
        'native\n${(sdk.stdout as String).split('\n')[1]}\nfalse\n',
      );
    },
  );

  test('CLI reports usage errors and writes each native file kind', () async {
    final output = StringBuffer(), errors = StringBuffer();
    final command = CompilerCommand(output, errors);
    expect(await command.run(['--help']), 0);
    expect(output.toString(), contains('Usage: dartc'));
    const source = 'test/compiler/fixtures/arithmetic.dart';
    expect(await command.run([source, '--kind', 'unknown']), 64);
    expect(errors.toString(), contains('Unknown output kind'));
    final directory = (Directory(
      'build/test',
    )..createSync(recursive: true)).createTempSync('cli-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final assets = NativeAssets(Target.host());
    final header = File.fromUri(directory.uri.resolve('api.h'));
    final existing = File.fromUri(directory.uri.resolve('existing.o'))
      ..writeAsStringSync('existing output');
    expect(
      await command.run([
        source,
        '-o',
        existing.path,
        '--sdk',
        'test/compiler/fixtures',
      ]),
      64,
    );
    expect(existing.readAsStringSync(), 'existing output');
    expect(errors.toString(), contains('Unknown option: --sdk'));
    for (final (kind, expected) in [
      ('object', assets.file('compiler/arithmetic.o')),
      ('static', assets.file('compiler/arithmetic.a')),
      ('shared', assets.library('compiler/arithmetic')),
    ]) {
      final file = File.fromUri(
        directory.uri.resolve(expected.uri.pathSegments.last),
      );
      expect(
        await command.run([
          source,
          '-o',
          file.path,
          if (kind != 'object') ...['--kind', kind],
          '--header',
          header.path,
        ]),
        0,
      );
      expect(file.readAsBytesSync(), expected.readAsBytesSync());
      expect(
        header.readAsStringSync(),
        assets.file('compiler/arithmetic.h').readAsStringSync(),
      );
    }
  });
}
