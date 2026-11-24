import 'dart:io';

import 'package:test/test.dart';

import '../support/compiler.dart';

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
    final built = Process.runSync(Platform.resolvedExecutable, [
      'tool/build.dart',
      '$path/bin/dartc',
    ]);
    expect((built.exitCode, built.stderr), (0, ''));
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
}
