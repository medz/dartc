@TestOn('mac-os')
@Tags(['native'])
@Timeout.factor(10)
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:dartc/driver.dart';
import 'package:dartc/hir.dart';
import 'package:dartc/lower.dart';
import 'package:dartc/optimize.dart';
import 'package:dartc/source.dart';
import 'package:dartc/translate.dart';
import 'package:test/test.dart';

import '../image/support.dart' show skipExecution;
import '../lower/support.dart';
import '../support/hosts.dart';
import '../support/compiler.dart';
import 'random_async.dart';
import 'random_dart.dart';
import 'random_patterns.dart';

/// Exit codes of the official runtime and of the compiled program.
Future<(int, int)> _both(String source) async {
  final directory = writeSources({'main.dart': source});
  final path = '${directory.path}/main.dart';
  final program = '${directory.path}/program';
  final official = await Process.run('$hostSdk/bin/dart', ['run', path]);
  var code = official.exitCode;
  for (final host in Host.all) {
    writeProgram(
      await compileProgram(path, CompileOptions(target: host.target)),
      program,
    );
    final compiled = await host.run(program);
    expect(
      compiled.output,
      official.stdout,
      reason: '${host.target}: ${compiled.errors}',
    );
    expect(
      compiled.code,
      official.exitCode,
      reason: '${host.target}: ${compiled.errors}',
    );
    if (code == official.exitCode) code = compiled.code;
  }
  return (official.exitCode, code);
}

/// Runs [body], telling what it throws.
String _caught(String body) =>
    '  try { $body }\n'
    "  on C3 { print('!C3'); } on C1 { print('!C1'); }\n"
    "  on K { print('!K'); } on C0 { print('!C0'); }\n"
    '  on UnsupportedError catch (e) { print(e); }\n'
    '  on TypeError catch (e) { print(e); }\n'
    "  on Error { print('!E'); }\n";

/// A program that prints what random functions give.
String _randomFunctions(int seed) {
  final generator = RandomDart(seed);
  final functions = generator.generate(25);
  final checks = [
    for (final (call, _) in generator.calls) _caught('print($call);'),
  ];
  return '$functions\nvoid main() {\n${checks.join()}}';
}

/// Runs [source] everywhere and compares what it prints.
Future<void> _compareRandom(String source, String reason) async {
  final directory = writeSources({'main.dart': source});
  final path = '${directory.path}/main.dart';
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
  final optimized = optimizeProgram(module);
  final again = HirInterpreter(optimized, maxSteps: steps);
  expect(again.run(), isNull, reason: reason);
  expect(again.output, official.stdout, reason: reason);
  final program = '${directory.path}/program';
  for (final host in Host.all) {
    for (final collectsAlways in [false, true]) {
      final lowered = lowerProgram(
        optimized,
        system: host.target.system,
        collectsAlways: collectsAlways,
      );
      host.write(lowered, program, entry: entrySymbol);
      final native = await host.run(program);
      final told = '${host.target}: $reason\n${native.errors}';
      expect(native.code, 0, reason: told);
      expect(native.output, official.stdout, reason: told);
    }
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
      await _compareRandom(_randomFunctions(seed), 'seed $seed');
    }, skip: skipExecution);
  }

  for (var seed = 0; seed < 4; seed++) {
    test('random patterns, seed $seed', () async {
      await _compareRandom(RandomPatterns(seed).generate(), 'seed $seed');
    }, skip: skipExecution);
  }

  for (var seed = 0; seed < 4; seed++) {
    test('random async functions, seed $seed', () async {
      await _compareRandom(RandomAsync(seed).generate(), 'seed $seed');
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
