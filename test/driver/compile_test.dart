@TestOn('mac-os')
@Tags(['native'])
@Timeout.factor(10)
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:dartc/driver.dart';
import 'package:dartc/source.dart';
import 'package:test/test.dart';

import '../image/support.dart' show skipExecution;
import '../support/compiler.dart';

void main() {
  test('a program outlives the reader of its output', () async {
    final directory = writeSources({
      'main.dart':
          "import 'dart:io';\nvoid main() { "
          "for (var i = 0; i < 100000; i++) { print('0123456789'); } exit(7); }",
    });
    final path = '${directory.path}/main.dart';
    final program = '${directory.path}/program';
    writeProgram(await compileProgram(path), program);
    for (final command in [program, '$hostSdk/bin/dart run $path']) {
      for (final output in ['| head -1', '| true']) {
        final result = await Process.run('/bin/bash', [
          '-c',
          '$command $output; echo "\${PIPESTATUS[0]}"',
        ]);
        expect('${result.stdout}'.trim().split('\n').last, '7');
      }
      final closed = await Process.run('/bin/bash', ['-c', '$command >&-']);
      expect(closed.exitCode, 7);
    }
  }, skip: skipExecution);

  test('the same source gives the same bytes', () async {
    final directory = writeSources({
      'main.dart': "import 'dart:io';\nvoid main() { exit(1); }",
    });
    final path = '${directory.path}/main.dart';
    final first = await compileProgram(path);
    expect(await compileProgram(path), first);
  });

  test('a program that cannot be compiled is reported', () async {
    final directory = writeSources({
      'main.dart': 'void main() { f(); }',
    });
    await expectLater(
      compileProgram('${directory.path}/main.dart'),
      throwsA(isA<CompileFailure>()),
    );
  });

  test('only programs can be run', () {
    // What is not ASCII is a part of the path too.
    final output = '${writeSources({}).path}/a program ü';
    int mode() => FileStat.statSync(output).mode & 0x1ff;
    writeOutput(Uint8List(4), output, isExecutable: false);
    final usual = mode();
    expect(usual & 0x49, 0);
    writeProgram(Uint8List(4), output);
    // Whoever may read it may run it.
    expect(mode(), usual | (usual & 0x124) >> 2);
    writeOutput(Uint8List(4), output, isExecutable: false);
    expect(mode(), usual);
  });

  test('writing replaces a file only when complete', () {
    final directory = writeSources({'program': 'old'});
    final output = '${directory.path}/program';
    writeProgram(File('/usr/bin/true').readAsBytesSync(), output);
    expect(Process.runSync(output, const []).exitCode, 0);
    expect(directory.listSync(), hasLength(1));
    expect(
      () => writeProgram(
        File('/usr/bin/true').readAsBytesSync(),
        '${directory.path}/missing/program',
      ),
      throwsA(isA<FileSystemException>()),
    );
    // A directory cannot be replaced by a file; nothing is left behind.
    final blocked = Directory('${directory.path}/blocked')..createSync();
    File('${blocked.path}/kept').createSync();
    expect(
      () => writeProgram(Uint8List(4), blocked.path),
      throwsA(isA<FileSystemException>()),
    );
    expect(directory.listSync(), hasLength(2));
  });
}
