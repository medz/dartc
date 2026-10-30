import 'dart:convert';
import 'dart:io';

import '../lib/src/legacy/driver/packages.dart';
import '../lib/src/legacy/source.dart';
import 'src/process.dart';

Map<String, List<int>?> _bootstrapInputs(String root) {
  final entry = File('$root/bin/dartc.dart');
  final runtime = File('$root/lib/src/legacy/runtime.dart');
  final packages = compilerPackages(entry.uri.toString(), root, null);
  final paths = {
    for (final target in [0, 1])
      for (final file in collectSources(
        entry.uri.toString(),
        runtime.uri.toString(),
        packages,
        target,
      ).files)
        file.input.path,
    '$root/lib/src/legacy/host.dart',
    '$root/lib/export.dart',
    '$root/tool/bundle_compiler.dart',
    '$root/tool/bootstrap.dart',
    '$root/tool/src/process.dart',
    '$root/test/legacy/behavior_test.dart',
    for (final file in Directory(
      '$root/test/legacy/fixtures',
    ).listSync(recursive: true).whereType<File>())
      file.path,
  };
  // A new, nearer configuration changes package mappings and language versions.
  var directory = entry.parent;
  while (true) {
    final path = '${directory.path}/.dart_tool/package_config.json';
    paths.add(path);
    if (File(path).existsSync() || directory.parent.path == directory.path)
      break;
    directory = directory.parent;
  }
  return {
    for (final path in paths)
      path: File(path).existsSync() ? File(path).readAsBytesSync() : null,
  };
}

void _checkInputs(Map<String, List<int>?> inputs) {
  for (final input in inputs.entries) {
    final file = File(input.key);
    final actual = file.existsSync() ? file.readAsBytesSync() : null;
    final expected = input.value;
    var same = actual == null && expected == null;
    if (actual != null &&
        expected != null &&
        actual.length == expected.length) {
      same = true;
      for (var i = 0; i < actual.length; i++) {
        if (actual[i] != expected[i]) {
          same = false;
          break;
        }
      }
    }
    if (!same) throw StateError('Bootstrap input changed: ${input.key}');
  }
}

Future<void> run(
  String executable,
  List<String> arguments, {
  bool native = false,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final result = await captureProcess(
    executable,
    arguments,
    environment: native ? {'PATH': '/usr/bin:/bin'} : null,
    includeParentEnvironment: !native,
    timeout: timeout,
  );
  stdout.add(result.stdoutBytes);
  stderr.add(result.stderrBytes);
  if (result.exitCode != 0 ||
      result.timedOut ||
      result.outputLimited ||
      result.startError != null ||
      result.captureError != null) {
    throw ProcessException(
      executable,
      arguments,
      jsonEncode(result.toJson()),
      result.exitCode ?? -1,
    );
  }
}

Future<void> main(List<String> args) async {
  final root = File.fromUri(Platform.script).parent.parent.absolute.path;
  final build = Directory('$root/build')..createSync(recursive: true);
  final sdk = Platform.resolvedExecutable;
  final source = '$root/bin/dartc.dart';
  final standard = '$root/lib/src/legacy/runtime.dart';
  final verifiedSeed = '${build.path}/dartc-seed';
  var seed = verifiedSeed;
  if (args.length == 2 && args[0] == '--seed') {
    seed = File(args[1]).absolute.path;
  } else if (args.isNotEmpty) {
    stderr.writeln(
      'Usage: dart tool/bootstrap.dart [--seed <native compiler>]',
    );
    exit(64);
  }
  final work = build.createTempSync('bootstrap-');
  final stage1 = '${work.path}/dartc-stage1';
  final stage2 = '${work.path}/dartc-stage2';
  final stage3 = '${work.path}/dartc-stage3';
  final seedCopy = File('${work.path}/dartc-seed');
  final bundler = '${work.path}/bundle_compiler';
  final bundledSource = File('${work.path}/compiler.dart');
  var passed = false;
  try {
    final input = File(seed);
    if (input.existsSync()) {
      input.copySync(seedCopy.path);
      stdout.writeln('Using native seed: $seed');
    } else {
      if (args.isNotEmpty) {
        throw StateError('Native seed not found: $seed.');
      }
      stdout.writeln(
        'No local native seed found. Building the initial seed with official Dart.',
      );
      await run(sdk, ['compile', 'exe', source, '-o', seedCopy.path]);
    }
    final inputs = _bootstrapInputs(root);
    void saveInputs() {
      File('${work.path}/inputs.json').writeAsStringSync(
        jsonEncode({
          'source': bundledSource.path,
          'entry': source,
          'runtime': standard,
          'inputSeed': seed,
          'sdk': {'path': sdk, 'version': Platform.version},
          'files': {
            for (final input in inputs.entries)
              input.key: input.value == null
                  ? null
                  : base64Encode(input.value!),
          },
        }),
      );
    }

    saveInputs();
    await run(seedCopy.path, [
      '$root/tool/bundle_compiler.dart',
      '--std',
      standard,
      '-o',
      bundler,
    ], native: true);
    _checkInputs(inputs);
    await run(bundler, [root, bundledSource.path], native: true);
    _checkInputs(inputs);
    inputs[bundledSource.path] = bundledSource.readAsBytesSync();
    saveInputs();
    Future<void> compile(String compiler, String output) async {
      await run(compiler, [
        bundledSource.path,
        '-o',
        output,
        '--std',
        standard,
      ], native: true);
      if (!File(output).existsSync() || File(output).lengthSync() == 0)
        throw StateError('Compiler produced no executable: $output');
      _checkInputs(inputs);
    }

    stdout.writeln('Building stage 1 with the seed copy.');
    await compile(seedCopy.path, stage1);
    stdout.writeln('Building stage 2 with stage 1.');
    await compile(stage1, stage2);
    stdout.writeln('Building stage 3 with stage 2.');
    await compile(stage2, stage3);
    final a = File(stage2).readAsBytesSync();
    final b = File(stage3).readAsBytesSync();
    if (a.length != b.length)
      throw StateError('Stage 2 and stage 3 differ in size.');
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i])
        throw StateError('Stage 2 and stage 3 differ at byte $i.');
    }
    stdout.writeln('Stage 2 and stage 3 are identical (${a.length} bytes).');
    await run(sdk, [
      '$root/test/legacy/behavior_test.dart',
      '--compiler',
      stage2,
      '--std',
      standard,
    ], timeout: const Duration(minutes: 10));
    _checkInputs(inputs);
    for (final stage in [stage1, stage2, stage3]) {
      File(stage)
          .copySync('${build.path}/${File(stage).uri.pathSegments.last}');
    }
    bundledSource.copySync('${build.path}/compiler.dart');
    File('${work.path}/inputs.json')
        .copySync('${build.path}/bootstrap-inputs.json');
    File(stage2).copySync(seedCopy.path);
    seedCopy.renameSync(verifiedSeed);
    passed = true;
    stdout.writeln(
      'Self-rebuild and behavior checks passed: ${build.path}/dartc-stage2',
    );
    stdout.writeln('Updated verified native seed: $verifiedSeed');
  } catch (error) {
    stderr.writeln(error);
    stderr.writeln('Bootstrap work retained at: ${work.path}');
    exitCode = 1;
  } finally {
    if (passed) work.deleteSync(recursive: true);
  }
}
