import 'dart:convert';
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
      'tool/bundle_compiler.dart',
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
    final build = Directory('${source.path}/build')..createSync();
    final bundler = '${build.path}/bundle_compiler';
    final bundledSource = '${build.path}/compiler.dart';
    final bundledCompiler = '${build.path}/dartc';
    await run(compiler, [
      '${source.path}/tool/bundle_compiler.dart',
      '--std',
      runtime.path,
      '-o',
      bundler,
    ], native: true);
    await run(bundler, [source.path, bundledSource], native: true);
    await run(compiler, [
      bundledSource,
      '--std',
      runtime.path,
      '-o',
      bundledCompiler,
    ], native: true);
    await run(Platform.resolvedExecutable, [
      '${source.path}/tool/package_release.dart',
      '--compiler',
      bundledCompiler,
    ]);
    final archive = Directory('${source.path}/build/release')
        .listSync()
        .whereType<File>()
        .singleWhere((file) => file.path.endsWith('.tar.gz'));
    final installed = Directory('${work.path}/installed')..createSync();
    await run('/usr/bin/tar', ['-xzf', archive.path, '-C', installed.path]);
    final bundle = installed.listSync().whereType<Directory>().single;
    if (Directory('${bundle.path}/lib').existsSync())
      throw StateError(
        'Native archive still contains external library sources.',
      );
    final standalone = File('${bundle.path}/bin/dartc')
        .copySync('${work.path}/dartc');
    bundle.deleteSync(recursive: true);
    final external = source.renameSync('${work.path}/external source');
    final app = File('${work.path}/main.dart')
      ..writeAsStringSync('''
import 'dart:ffi';
import 'package:dartc/export.dart';
@Export<Int64 Function(Int64)>()
int identity(int value) => value;
void main() { print(identity(releaseDependency())); }
''');
    final executable = '${work.path}/app';
    await run(standalone.path, [app.path, '-o', executable], native: true);
    final result = await run(executable, [], native: true);
    if (result.stdout != '73\n' || result.stderr != '') {
      throw StateError('Packaged dependency produced unexpected output.');
    }
    // Restore the original path with different contents: only explicit --std
    // may select it; a default build must continue using the embedded sources.
    external.renameSync(source.path);
    File('${source.path}/support/release_value_part.dart').writeAsStringSync(
      "part of 'release%20value.dart';\nconst int partValue = 97;\n",
    );
    final overrideApp = File('${work.path}/override.dart')
      ..writeAsStringSync('void main() { print(releaseDependency()); }\n');
    for (final override in [false, true, false]) {
      await run(standalone.path, [
        overrideApp.path,
        '-o',
        executable,
        if (override) ...['--std', runtime.path],
      ], native: true);
      final output = await run(executable, [], native: true);
      if (output.stdout != (override ? '97\n' : '73\n'))
        throw StateError(
          'Explicit runtime source selection was not preserved.',
        );
    }
    source.deleteSync(recursive: true);
    final values = File('$root/test/fixtures/values.dart')
        .copySync('${work.path}/values.dart');
    final expected = await run(Platform.resolvedExecutable, [
      values.path,
      'alpha',
      '你好',
    ]);
    await run(standalone.path, [values.path, '-o', executable], native: true);
    final actual = await run(executable, ['alpha', '你好'], native: true);
    if (actual.stdout != expected.stdout || actual.stderr != expected.stderr)
      throw StateError('Standalone compiler values differ from the SDK.');
    final mapped = Directory('${work.path}/mapped/lib')
      ..createSync(recursive: true);
    File('${mapped.path}/export.dart')
        .writeAsStringSync('int mappedValue() => 118;\n');
    final config = File('${work.path}/.dart_tool/package_config.json');
    config.parent.createSync();
    config.writeAsStringSync(
      jsonEncode({
        'configVersion': 2,
        'packages': [
          {'name': 'dartc', 'rootUri': '../mapped/', 'packageUri': 'lib/'},
        ],
      }),
    );
    app.writeAsStringSync(
      "import 'package:dartc/export.dart';\n"
      'void main() { print(mappedValue()); }\n',
    );
    await run(standalone.path, [app.path, '-o', executable], native: true);
    final mappedResult = await run(executable, [], native: true);
    if (mappedResult.stdout != '118\n' || mappedResult.stderr != '')
      throw StateError(
        'Embedded package replaced an explicit package mapping.',
      );
    passed = true;
    stdout.writeln(
      'Standalone native compiler preserves bundled sources, explicit overrides and behavior.',
    );
  } finally {
    if (passed) {
      work.deleteSync(recursive: true);
    } else {
      stderr.writeln('Package test retained at: ${work.path}');
    }
  }
}
