import 'dart:io';

import '../tool/src/process.dart';

Future<ProcessOutcome> run(
  String executable,
  List<String> arguments, {
  bool native = false,
}) async {
  final result = await captureProcess(
    executable,
    arguments,
    environment: native ? {'PATH': '/usr/bin:/bin'} : null,
    includeParentEnvironment: !native,
    timeout: const Duration(minutes: 2),
  );
  if (result.exitCode != 0 ||
      result.timedOut ||
      result.outputLimited ||
      result.startError != null ||
      result.captureError != null) {
    throw StateError('${result.toJson()}\n${result.stdout}${result.stderr}');
  }
  return result;
}

Future<void> main(List<String> args) async {
  if (args.length != 2 || args[0] != '--compiler') {
    stderr.writeln(
      'Usage: dart test/package_release_test.dart --compiler <native dartc>',
    );
    exitCode = 64;
    return;
  }
  final compiler = File(args[1]).absolute.path;
  final root = File.fromUri(Platform.script).parent.parent.path;
  final work = Directory.systemTemp.createTempSync('dartc-package-test-');
  var passed = false;
  try {
    final source = Directory('${work.path}/source bundle')..createSync();
    for (final relative in [
      'tool/package_release.dart',
      'pubspec.yaml',
      'LICENSE',
      for (final file in Directory('$root/lib').listSync(recursive: true))
        if (file is File && file.path.endsWith('.dart'))
          file.path.substring(root.length + 1),
    ]) {
      final destination = File('${source.path}/$relative');
      destination.parent.createSync(recursive: true);
      File('$root/$relative').copySync(destination.path);
    }
    final runtime = File('${source.path}/lib/src/runtime.dart');
    runtime.writeAsStringSync(
      "import 'runtime/release_dependency.dart';\n${runtime.readAsStringSync()}",
    );
    File('${source.path}/lib/src/std/core.dart').writeAsStringSync(
      "\nexport 'core/release_dependency.dart';\n",
      mode: FileMode.append,
    );
    final dependencies = {
      'lib/src/runtime/release_dependency.dart':
          "import '../../../support/release%20value.dart';\n"
          'int rtReleaseDependency() => releaseValue();\n',
      'lib/src/std/core/release_dependency.dart':
          "import '../../../../support/release%20value.dart';\n"
          'int releaseDependency() => releaseValue();\n',
      'support/release value.dart':
          "part 'release_value_part.dart';\n"
          'int releaseValue() => partValue;\n',
      'support/release_value_part.dart':
          "part of 'release%20value.dart';\n"
          'const int partValue = 73;\n',
    };
    for (final entry in dependencies.entries) {
      final file = File('${source.path}/${entry.key}');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(entry.value);
    }
    await run(Platform.resolvedExecutable, [
      '${source.path}/tool/package_release.dart',
      '--compiler',
      compiler,
    ]);
    final archive = Directory('${source.path}/build/release')
        .listSync()
        .whereType<File>()
        .singleWhere((file) => file.path.endsWith('.tar.gz'));
    final installed = Directory('${work.path}/installed')..createSync();
    await run('/usr/bin/tar', ['-xzf', archive.path, '-C', installed.path]);
    final bundle = installed.listSync().whereType<Directory>().single;
    source.deleteSync(recursive: true);
    final app = File('${work.path}/main.dart')
      ..writeAsStringSync('void main() { print(releaseDependency()); }\n');
    final executable = '${work.path}/app';
    await run('${bundle.path}/bin/dartc', [
      app.path,
      '-o',
      executable,
    ], native: true);
    final result = await run(executable, [], native: true);
    if (result.stdout != '73\n' || result.stderr != '') {
      throw StateError('Packaged dependency produced unexpected output.');
    }
    passed = true;
    stdout.writeln(
      'Native archive compiles with transitive runtime and core dependencies.',
    );
  } finally {
    if (passed) {
      work.deleteSync(recursive: true);
    } else {
      stderr.writeln('Package test retained at: ${work.path}');
    }
  }
}
