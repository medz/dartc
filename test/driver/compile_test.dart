@TestOn('mac-os')
@Tags(['native'])
@Timeout.factor(10)
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:dartc/driver.dart';
import 'package:dartc/emit.dart';
import 'package:dartc/hir.dart';
import 'package:dartc/image.dart';
import 'package:dartc/lower.dart';
import 'package:dartc/source.dart';
import 'package:dartc/translate.dart';
import 'package:test/test.dart';

import '../image/support.dart' show skipExecution;
import '../lower/support.dart';
import '../support/new_compiler.dart';
import 'random_dart.dart';

/// Exit codes of the official runtime and of the compiled program.
Future<(int, int)> _both(String source) async {
  final directory = writeSources({'main.dart': source});
  final path = '${directory.path}/main.dart';
  final program = '${directory.path}/program';
  writeProgram(await compileProgram(path), program);
  final official = await Process.run('$hostSdk/bin/dart', ['run', path]);
  final compiled = await Process.run(program, const []);
  expect(compiled.stdout, official.stdout);
  return (official.exitCode, compiled.exitCode);
}

/// Runs [body], telling what it throws.
String _caught(String body) =>
    '  try { $body }\n'
    "  on C3 { print('!C3'); } on C1 { print('!C1'); }\n"
    "  on K { print('!K'); } on C0 { print('!C0'); }\n"
    '  on UnsupportedError catch (e) { print(e); }\n'
    '  on TypeError catch (e) { print(e); }\n'
    "  on Error { print('!E'); }\n";

/// Runs random functions everywhere and compares what they print.
Future<void> _compareRandom(int seed) async {
  final generator = RandomDart(seed);
  final functions = generator.generate(25);
  final checks = [
    for (final (call, _) in generator.calls) _caught('print($call);'),
  ];
  final directory = writeSources({
    'main.dart': '$functions\nvoid main() {\n${checks.join()}}',
  });
  final path = '${directory.path}/main.dart';
  final reason = 'seed $seed';
  final official = await Process.run('$hostSdk/bin/dart', ['run', path]);
  expect(official.exitCode, 0, reason: '$reason: ${official.stderr}');
  final sdk = await packagedSdk();
  final module = translateProgram(await loadProgram(path, sdk: sdk));
  // The official runtime has shown that the program ends.
  const steps = 1 << 40;
  final interpreter = HirInterpreter(module, maxSteps: steps);
  expect(interpreter.run(), isNull, reason: reason);
  expect(interpreter.output, official.stdout, reason: reason);
  final machineLevel = LoweredRun(module, maxSteps: steps);
  expect(machineLevel.code, isNull, reason: reason);
  expect(machineLevel.output, official.stdout, reason: reason);
  final program = '${directory.path}/program';
  for (final collectsAlways in [false, true]) {
    final code = emitArm64(
      lowerProgram(module, collectsAlways: collectsAlways),
    );
    writeProgram(
      linkMacho(code, entry: entrySymbol, identifier: 'random'),
      program,
    );
    final native = await Process.run(program, const []);
    expect(native.exitCode, 0, reason: reason);
    expect(native.stdout, official.stdout, reason: reason);
  }
}

void main() {
  test('programs agree with the official runtime', () async {
    for (final body in [
      'exit(1 + 2 * 3);',
      '',
      'exit(0);',
      'exit(255);',
      'exit(256);',
      'exit(300);',
      'exit(-1);',
      'exit(-9223372036854775808);',
      'exit(0xffffffffffffffff);',
      'exit(7); exit(8);',
      'return; exit(8);',
      '1 + 2; { exit(~(5 - 9)); }',
      "print('hello');",
      r"print('é😀\uD800|\uDC00 \x00\r\n'); print(''); print('b'); exit(3);",
      "for (var i = 0; i < 5000; i++) { print('0123456789'); } exit(9);",
      'var n = 0; for (var i = 0; i < 9; i++) { n += i * i; } exit(n);',
      'exit(5.5 % -2 == 1.5 && -7 % 3 == 2 ? 11 : 12);',
    ]) {
      final (official, compiled) = await _both(
        "import 'dart:io';\nvoid main() { $body }",
      );
      expect(compiled, official, reason: body);
    }
  }, skip: skipExecution);

  for (final name in [
    'hello',
    'print_integers',
    'map_sum',
    'persistent_cell',
  ]) {
    test('the program $name agrees', () async {
      final source = File('tool/bench/fixtures/$name.dart').readAsStringSync();
      final (official, compiled) = await _both(source);
      expect(compiled, official);
    }, skip: skipExecution);
  }

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

  for (var seed = 0; seed < 12; seed++) {
    test('random functions, seed $seed', () async {
      await _compareRandom(seed);
    }, skip: skipExecution);
  }

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
      'main.dart': 'external void f(); void main() { f(); }',
    });
    await expectLater(
      compileProgram('${directory.path}/main.dart'),
      throwsA(isA<CompileFailure>()),
    );
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

  test('the command line reports problems and its usage', () async {
    final directory = writeSources({
      'good.dart': "import 'dart:io';\nvoid main() { exit(9); }",
      'bad.dart': 'void main() {\n  (1, 2);\n}',
    });
    Future<ProcessResult> run(List<String> arguments) => Process.run(
      '$hostSdk/bin/dart',
      ['run', 'tool/compile.dart', ...arguments],
    );
    final output = '${directory.path}/program';
    final good = await run(['${directory.path}/good.dart', output]);
    expect(good.exitCode, 0, reason: '${good.stderr}');
    expect(Process.runSync(output, const []).exitCode, 9);
    File(output).deleteSync();
    final bad = await run(['${directory.path}/bad.dart', output]);
    expect(bad.exitCode, 1);
    expect(
      bad.stderr,
      '${directory.path}/bad.dart:2:3: '
      'Not supported yet: record literal.\n',
    );
    expect(File(output).existsSync(), isFalse);
    expect((await run([])).exitCode, 64);
  }, skip: skipExecution);
}
