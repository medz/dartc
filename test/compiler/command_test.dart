@Tags(['assets', 'native'])
library;

import 'dart:io';

import 'package:dartc/src/compiler/cli/command.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
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
