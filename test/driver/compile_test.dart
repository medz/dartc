@TestOn('mac-os')
@Tags(['native'])
@Timeout.factor(4)
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:dartc/driver.dart';
import 'package:dartc/hir.dart';
import 'package:dartc/source.dart';
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
  writeProgram(await compileProgram(path, sdk: hostSdk), program);
  final official = await Process.run('$hostSdk/bin/dart', ['run', path]);
  final compiled = await Process.run(program, const []);
  expect(compiled.stdout, official.stdout);
  return (official.exitCode, compiled.exitCode);
}

/// A check that [found] is [printed], as the official runtime printed it.
String _same(String found, Kind kind, String printed) {
  if (kind != .float) return '$found == $printed';
  return switch (printed) {
    'NaN' => '$found != $found',
    'Infinity' => '$found == double.infinity',
    '-Infinity' => '$found == -double.infinity',
    '0.0' => '$found == 0 && 1 / $found > 0',
    '-0.0' => '$found == 0 && 1 / $found < 0',
    _ => '$found == $printed',
  };
}

/// Runs random functions everywhere and compares every bit of their results.
Future<void> _compareRandom(int seed) async {
  final generator = RandomDart(seed);
  final functions = generator.generate(25);
  final calls = generator.calls;
  final directory = writeSources({
    'print.dart':
        '$functions\nvoid main() {\n'
        '${calls.map((call) => '  print(${call.$1});\n').join()}}',
  });
  final official = await Process.run('$hostSdk/bin/dart', [
    'run',
    '${directory.path}/print.dart',
  ]);
  expect(official.exitCode, 0, reason: 'seed $seed: ${official.stderr}');
  final printed = '${official.stdout}'.trim().split('\n');
  expect(printed, hasLength(calls.length));
  // Exits with the number of the first result that differs.
  final checks = [
    for (final (i, (call, kind)) in calls.indexed)
      '  final ${kind.name} r$i = $call;\n'
          '  if (!(${_same('r$i', kind, printed[i])})) exit(${i + 1});\n',
  ];
  final source =
      "import 'dart:io';\n$functions\n"
      'void main() {\n${checks.join()}  exit(100);\n}';
  String reason(int? code) => code != null && code > 0 && code <= calls.length
      ? 'seed $seed: ${calls[code - 1].$1} is not ${printed[code - 1]}'
      : 'seed $seed: ended with $code';
  final module = await translate(source);
  final dartLevel = HirInterpreter(module).run();
  expect(dartLevel, 100, reason: reason(dartLevel));
  final machineLevel = runLowered(module);
  expect(machineLevel, 100, reason: reason(machineLevel));
  final path = '${directory.path}/main.dart';
  File(path).writeAsStringSync(source);
  final program = '${directory.path}/program';
  writeProgram(await compileProgram(path, sdk: hostSdk), program);
  final native = (await Process.run(program, const [])).exitCode;
  expect(native, 100, reason: reason(native));
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
      'var n = 0; for (var i = 0; i < 9; i++) { n += i * i; } exit(n);',
      'exit(5.5 % -2 == 1.5 && -7 % 3 == 2 ? 11 : 12);',
    ]) {
      final (official, compiled) = await _both(
        "import 'dart:io';\nvoid main() { $body }",
      );
      expect(compiled, official, reason: body);
    }
  }, skip: skipExecution);

  test('a wrong result would be noticed', () async {
    // Each kind of check must fail for a value that differs slightly.
    for (final (found, kind, printed) in [
      ('1', Kind.integer, '2'),
      ('true', Kind.boolean, 'false'),
      ('0.1', Kind.float, '0.10000000000000002'),
      ('0.0', Kind.float, '-0.0'),
      ('-0.0', Kind.float, '0.0'),
      ('1.0', Kind.float, 'NaN'),
      ('double.nan', Kind.float, '1.0'),
      ('1e308', Kind.float, 'Infinity'),
      ('double.infinity', Kind.float, '-Infinity'),
    ]) {
      final module = await translate(
        "import 'dart:io';\nvoid main() { final ${kind.name} r = $found; "
        'if (!(${_same('r', kind, printed)})) exit(1); exit(100); }',
      );
      expect(HirInterpreter(module).run(), 1, reason: '$found, $printed');
      expect(runLowered(module), 1, reason: '$found, $printed');
    }
  });

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
    final first = await compileProgram(path, sdk: hostSdk);
    expect(await compileProgram(path, sdk: hostSdk), first);
  });

  test('a program that cannot be compiled is reported', () async {
    final directory = writeSources({'main.dart': 'void main() { "x"; }'});
    await expectLater(
      compileProgram('${directory.path}/main.dart', sdk: hostSdk),
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
      'bad.dart': 'void main() {\n  "x";\n}',
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
      'Not supported yet: simple string literal.\n',
    );
    expect(File(output).existsSync(), isFalse);
    expect((await run([])).exitCode, 64);
  }, skip: skipExecution);
}
