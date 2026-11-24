import 'dart:io';

import 'package:dartc/native.dart';
import 'package:test/test.dart';

import '../support/compiler.dart';

/// Whether to let the compiler compile itself, which takes many minutes and
/// gigabytes of memory.
final _compilesItself =
    Platform.environment['DARTC_SELF_HOSTING']?.isNotEmpty ?? false;

void _build(String output, {String? compiler}) {
  final built = Process.runSync(Platform.resolvedExecutable, [
    'tool/build.dart',
    if (compiler != null) '--with=$compiler',
    output,
  ]);
  expect((built.exitCode, built.stderr), (0, ''));
}

void main() {
  test('only what finds the package uses isolates', () {
    final using = [
      for (final file in Directory('lib').listSync(recursive: true))
        if (file is File &&
            file.path.endsWith('.dart') &&
            file.readAsStringSync().contains("import 'dart:isolate'"))
          file.path,
    ];
    expect(using, ['lib/src/driver/packaged.dart']);
  });

  test('the compiler is one program that needs no other files', () {
    final directory = writeSources({
      'main.dart': "void main(List<String> names) => print('hello \$names');",
    });
    final path = directory.path;
    _build('$path/bin/dartc');
    final compiled = Process.runSync(
      '$path/bin/dartc',
      const ['main.dart', '-o', 'main'],
      workingDirectory: path,
      environment: const {'PATH': '/usr/bin:/bin'},
      includeParentEnvironment: false,
    );
    expect((compiled.exitCode, compiled.stderr), (0, ''));
    final program = Process.runSync('$path/main', const ['a', 'b']);
    expect((program.exitCode, program.stdout), (0, 'hello [a, b]\n'));
  }, timeout: const Timeout.factor(6));

  test(
    'the compiler that it compiled is as good',
    () {
      final path = writeSources({}).path;
      final [first, second, third] = [
        for (final name in ['first', 'second', 'third']) '$path/$name',
      ];
      _build(first);
      _build(second, compiler: first);
      // Programs are the same for all systems.
      final programs = Directory('tool/bench/programs').listSync();
      for (final program in programs.whereType<File>()) {
        for (final target in Target.values) {
          List<int> compile(String compiler) {
            final result = Process.runSync(compiler, [
              program.path,
              '--target=${target.label.replaceAll('_', '-')}',
              '-o',
              '$path/program',
            ]);
            expect((result.exitCode, result.stderr), (0, ''));
            return File('$path/program').readAsBytesSync();
          }

          expect(
            compile(second),
            compile(first),
            reason: '${program.path} for $target',
          );
        }
      }
      _build(third, compiler: second);
      expect(File(third).readAsBytesSync(), File(second).readAsBytesSync());
    },
    timeout: const Timeout(Duration(minutes: 30)),
    skip: !_compilesItself,
  );
}
