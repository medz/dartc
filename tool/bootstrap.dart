import 'dart:io';

void run(String executable, List<String> arguments, {bool native = false}) {
  final result = Process.runSync(
    executable,
    arguments,
    environment: native ? {'PATH': '/usr/bin:/bin'} : null,
    includeParentEnvironment: !native,
  );
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  if (result.exitCode != 0) {
    throw ProcessException(
      executable,
      arguments,
      'Command failed.',
      result.exitCode,
    );
  }
}

void main() {
  final root = File.fromUri(Platform.script).parent.parent.absolute.path;
  final build = Directory('$root/build')..createSync(recursive: true);
  final sdk = Platform.resolvedExecutable;
  final source = '$root/bin/dartc.dart';
  final standard = '$root/lib/src/runtime.dart';
  final seed = '${build.path}/seed';
  final stage1 = '${build.path}/dartc-stage1';
  final stage2 = '${build.path}/dartc-stage2';
  final stage3 = '${build.path}/dartc-stage3';
  try {
    stdout.writeln('Building the seed with official Dart.');
    run(sdk, ['compile', 'exe', source, '-o', seed]);
    stdout.writeln('Building stage 1 with the seed.');
    run(seed, [source, '-o', stage1, '--std', standard], native: true);
    stdout.writeln('Building stage 2 with stage 1.');
    run(stage1, [source, '-o', stage2, '--std', standard], native: true);
    stdout.writeln('Building stage 3 with stage 2.');
    run(stage2, [source, '-o', stage3, '--std', standard], native: true);
    final a = File(stage2).readAsBytesSync();
    final b = File(stage3).readAsBytesSync();
    if (a.length != b.length)
      throw StateError('Stage 2 and stage 3 differ in size.');
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i])
        throw StateError('Stage 2 and stage 3 differ at byte $i.');
    }
    stdout.writeln('Stage 2 and stage 3 are identical (${a.length} bytes).');
    run(sdk, [
      '$root/test/behavior_test.dart',
      '--compiler',
      stage2,
      '--std',
      standard,
    ]);
    stdout.writeln('Self-hosting verified: $stage2');
  } catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}
