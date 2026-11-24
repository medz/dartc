import 'dart:io';

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

/// The official runtime has shown that programs end.
const _steps = 1 << 40;

/// Checks that [source] prints and exits as the official runtime says, at every
/// level, and when collecting always. It must print something, so that it
/// cannot agree by doing nothing.
void agrees(
  String name,
  String source, {
  String imports = '',

  /// Whether it creates too much to collect always, or depends on time.
  bool isLong = false,
}) => test(name, () async {
  final text = "import 'dart:io';\n$imports\n$source";
  final directory = writeSources({'main.dart': text});
  final path = '${directory.path}/main.dart';
  final official = await Process.run('$hostSdk/bin/dart', ['run', path]);
  expect(official.stdout, isNotEmpty, reason: '${official.stderr}');
  final module = translateProgram(
    await loadProgram(path, sdk: await packagedSdk()),
  );
  final interpreter = HirInterpreter(module, maxSteps: _steps);
  expect(interpreter.run() ?? 0, official.exitCode);
  expect(interpreter.output, official.stdout);
  // Stack traces, which follow, are not printed.
  final errors = interpreter.errors, reported = '${official.stderr}';
  expect(reported, startsWith(errors));
  expect(reported.substring(errors.length), anyOf('', startsWith('#0 ')));
  final lowered = LoweredRun(module, maxSteps: _steps);
  expect(lowered.code ?? 0, official.exitCode);
  expect(lowered.output, official.stdout);
  expect(lowered.errors, errors);
  if (skipExecution != null) return;
  for (final collectsAlways in [false, if (!isLong) true]) {
    final program = '${directory.path}/program-$collectsAlways';
    final code = emitArm64(
      lowerProgram(module, collectsAlways: collectsAlways),
    );
    writeProgram(
      linkMacho(code, entry: entrySymbol, identifier: 'dartc-test'),
      program,
    );
    final result = await Process.run(program, const []);
    final reason = 'collecting always: $collectsAlways';
    expect(result.exitCode, official.exitCode, reason: reason);
    expect(result.stdout, official.stdout, reason: reason);
    expect(result.stderr, errors, reason: reason);
  }
}, timeout: const Timeout.factor(6));

/// Prints the digits of small numbers, and other values.
const tools = r'''
void digit(int n) {
  switch (n) {
    case 0: print('0'); case 1: print('1'); case 2: print('2');
    case 3: print('3'); case 4: print('4'); case 5: print('5');
    case 6: print('6'); case 7: print('7'); case 8: print('8');
    case 9: print('9');
  }
}
void number(int n) {
  if (n < 0) { print('-'); n = -n; }
  if (n > 9) number(n ~/ 10);
  digit(n % 10);
  print('.');
}
void truth(bool b) => b ? print('true') : print('false');
int trace(int n) { number(n); return n; }
''';
