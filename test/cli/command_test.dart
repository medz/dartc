import 'dart:io';

import 'package:dartc/cli.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  test('CLI reports usage errors and writes a native object', () async {
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
    final file = File.fromUri(directory.uri.resolve('cli.o'));
    expect(await command.run([source, '-o', file.path]), 0);
    expect(
      file.readAsBytesSync(),
      NativeAssets(Target.host())
          .file('compiler/arithmetic.o')
          .readAsBytesSync(),
    );
  });
}
