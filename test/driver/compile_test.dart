@TestOn('mac-os')
@Tags(['native'])
@Timeout.factor(4)
library;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dartc/driver.dart';
import 'package:dartc/hir.dart';
import 'package:dartc/source.dart';
import 'package:test/test.dart';

import '../image/support.dart' show skipExecution;
import '../lower/lower_test.dart' show runLowered;
import '../support/new_compiler.dart';

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

/// A random expression over the supported operators.
String _expression(Random random, int depth) {
  const literals = [
    '0',
    '1',
    '2',
    '255',
    '1_000_003',
    '0xffffffffffffffff',
    '0x8000000000000000',
    '9223372036854775807',
    '-9223372036854775808',
    '0x123456789abcdef',
  ];
  if (depth == 0 || random.nextInt(8) == 0) {
    return random.nextBool()
        ? literals[random.nextInt(literals.length)]
        : '${random.nextInt(1 << 32)}';
  }
  if (random.nextInt(5) == 0) {
    final operator = random.nextBool() ? '-' : '~';
    return '$operator(${_expression(random, depth - 1)})';
  }
  final operator = const ['+', '-', '*', '&', '|', '^'][random.nextInt(6)];
  final left = _expression(random, depth - 1);
  final right = _expression(random, depth - 1);
  // Often without parentheses, so precedence decides the grouping.
  return random.nextBool()
      ? '$left $operator $right'
      : '($left) $operator ($right)';
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
    ]) {
      final (official, compiled) = await _both(
        "import 'dart:io';\nvoid main() { $body }",
      );
      expect(compiled, official, reason: body);
    }
  }, skip: skipExecution);

  test('random expressions agree with the official runtime', () async {
    final random = Random(20261123);
    final expressions = [for (var i = 0; i < 40; i++) _expression(random, 6)];
    final directory = writeSources({
      'print.dart':
          'void main() {\n${expressions.map((e) => 'print($e);\n').join()}}',
    });
    final official = await Process.run('$hostSdk/bin/dart', [
      'run',
      '${directory.path}/print.dart',
    ]);
    expect(official.exitCode, 0, reason: '${official.stderr}');
    final values = '${official.stdout}'.trim().split('\n').map(int.parse);
    expect(values, hasLength(expressions.length));
    for (final (i, value) in values.indexed) {
      final source =
          "import 'dart:io';\nvoid main() { exit(${expressions[i]}); }";
      final module = await translate(source);
      expect(HirInterpreter(module).run(), value, reason: expressions[i]);
      expect(runLowered(module), value, reason: expressions[i]);
      if (i % 8 != 0) continue;
      final (code, compiled) = await _both(source);
      expect(compiled, code, reason: expressions[i]);
      expect(compiled, value & 0xff, reason: expressions[i]);
    }
  }, skip: skipExecution);

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
