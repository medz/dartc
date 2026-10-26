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

void main(List<String> args) {
  final root = File.fromUri(Platform.script).parent.parent.absolute.path;
  final build = Directory('$root/build')..createSync(recursive: true);
  final sdk = Platform.resolvedExecutable;
  final source = '$root/bin/dartc.dart';
  final standard = '$root/lib/src/runtime.dart';
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
  final stage1 = '${build.path}/dartc-stage1';
  final stage2 = '${build.path}/dartc-stage2';
  final stage3 = '${build.path}/dartc-stage3';
  final seedCopy = File('${build.path}/dartc-bootstrap-seed');
  var ownsCopy = false;
  try {
    final input = File(seed);
    if (input.existsSync()) {
      if (seedCopy.existsSync() &&
          FileSystemEntity.identicalSync(input.path, seedCopy.path)) {
        throw ArgumentError('The bootstrap temporary copy cannot be the seed.');
      }
      ownsCopy = true;
      input.copySync(seedCopy.path);
      stdout.writeln('Using native seed: $seed');
    } else {
      if (args.isNotEmpty) {
        throw StateError('Native seed not found: $seed.');
      }
      ownsCopy = true;
      stdout.writeln(
        'No local native seed found. Building the initial seed with official Dart.',
      );
      run(sdk, ['compile', 'exe', source, '-o', seedCopy.path]);
    }
    stdout.writeln('Building stage 1 with the seed copy.');
    run(seedCopy.path, [source, '-o', stage1, '--std', standard], native: true);
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
    File(stage2).copySync(seedCopy.path);
    seedCopy.renameSync(verifiedSeed);
    stdout.writeln('Self-hosting verified: $stage2');
    stdout.writeln('Updated verified native seed: $verifiedSeed');
  } catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  } finally {
    if (ownsCopy && seedCopy.existsSync()) seedCopy.deleteSync();
  }
}
