@TestOn('mac-os')
@Tags(['native'])
@Timeout.factor(8)
library;

import 'dart:io';

import 'package:dartc/driver.dart';
import 'package:test/test.dart';

import '../support/compiler.dart';
import '../support/hosts.dart';

/// Throws in functions, methods, closures and `async` functions, and ends with
/// what nothing catches.
const _source = r'''
int f(int n) => n == 0 ? throw StateError('x') : f(n - 1);

class C {
  void m() => throw ArgumentError('y');
  int get g => throw 'g';
}

Future<void> later() async {
  await null;
  throw 'z';
}

Future<void> deeper() async {
  await later();
}

void show(void Function() f) {
  try {
    f();
  } catch (e, s) {
    print(s);
  }
}

void main() async {
  show(() => f(2));
  show(() => C().m());
  show(() => C().g);
  print(StackTrace.current);
  try {
    await deeper();
  } catch (e, s) {
    print(s);
  }
  try {
    throw 'here';
  } catch (e, s) {
    print(s);
  }
  f(1);
}
''';

void main() {
  test('traces tell what the official runtime tells', () async {
    final directory = writeSources({'main.dart': _source});
    final path = '${directory.path}/main.dart';
    final official = '${directory.path}/official';
    final compiled = Process.runSync('$hostSdk/bin/dart', [
      'compile',
      'exe',
      path,
      '-o',
      official,
    ]);
    expect(compiled.exitCode, 0, reason: '${compiled.stderr}');
    final expected = Process.runSync(official, const []);
    final program = '${directory.path}/program';
    for (final host in Host.all) {
      writeProgram(
        await compileProgram(path, CompileOptions(target: host.target)),
        program,
      );
      final run = await host.run(program);
      expect(run.output, expected.stdout, reason: '${host.target}');
      expect(run.errors, expected.stderr, reason: '${host.target}');
      expect(run.code, expected.exitCode, reason: '${host.target}');
    }
  });
}
