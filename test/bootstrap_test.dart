import 'dart:convert';
import 'dart:io';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

bool equalBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}

Future<void> main(List<String> args) async {
  if (args.length != 2 || args[0] != '--compiler') {
    stderr.writeln(
      'Usage: dart test/bootstrap_test.dart --compiler <native compiler>',
    );
    exitCode = 64;
    return;
  }
  final root = File.fromUri(Platform.script).parent.parent.path;
  final seed = File(args[1]).absolute;
  final work = Directory.systemTemp.createTempSync('dartc-bootstrap-test-');
  var passed = false;
  try {
    final source = Directory('${work.path}/source')..createSync();
    for (final folder in ['bin', 'lib', 'tool', 'test']) {
      for (final file
          in Directory('$root/$folder')
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => file.path.endsWith('.dart'))) {
        final destination = File(
          '${source.path}/${file.path.substring(root.length + 1)}',
        );
        destination.parent.createSync(recursive: true);
        file.copySync(destination.path);
      }
    }
    File('$root/pubspec.yaml').copySync('${source.path}/pubspec.yaml');
    final build = Directory('${source.path}/build')..createSync();
    final published = [
      for (final name in ['seed', 'stage1', 'stage2', 'stage3'])
        seed.copySync('${build.path}/dartc-$name'),
    ];
    final before = seed.readAsBytesSync();
    for (final item in {
      'lib/src/runtime.dart': 'Building stage 1 with the seed copy.',
      'test/fixtures/values.dart': 'Stage 2 and stage 3 are identical (',
      'bin/.dart_tool/package_config.json':
          'Building stage 1 with the seed copy.',
    }.entries) {
      final relative = item.key;
      final changed = File('${source.path}/$relative');
      final original = changed.existsSync() ? changed.readAsBytesSync() : null;
      var edited = false;
      final process = await Process.start(
        Platform.resolvedExecutable,
        ['${source.path}/tool/bootstrap.dart'],
        workingDirectory: source.path,
        environment: const {'PATH': '/usr/bin:/bin', 'CI': 'true'},
        includeParentEnvironment: false,
      );
      final output = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .map((line) {
            if (!edited && line.startsWith(item.value)) {
              edited = true;
              changed.parent.createSync(recursive: true);
              final replacement = File('${changed.path}.next');
              replacement.writeAsBytesSync([
                if (original != null) ...original,
                ...utf8.encode(
                  original == null
                      ? '{"configVersion":2,"packages":[]}\n'
                      : '\n// Edited while bootstrap was running.\n',
                ),
              ]);
              replacement.renameSync(changed.path);
            }
            return line;
          })
          .join('\n');
      final errors = process.stderr.transform(utf8.decoder).join();
      await process.stdin.close();
      final status = await process.exitCode.timeout(
        const Duration(minutes: 12),
        onTimeout: () {
          process.kill(ProcessSignal.sigkill);
          throw StateError('Bootstrap did not finish.');
        },
      );
      final stdoutText = await output;
      final stderrText = await errors;
      File('${work.path}/case-${relative.split('/').last}.json')
          .writeAsStringSync(
            jsonEncode({
              'changed': relative,
              'exitCode': status,
              'stdout': stdoutText,
              'stderr': stderrText,
            }),
          );
      check(edited, 'Did not edit the input while bootstrap was running.');
      check(
        status == 1 && stderrText.contains('Bootstrap input changed:'),
        'Bootstrap accepted an edited input ($relative):\n$stdoutText\n$stderrText',
      );
      if (relative == 'test/fixtures/values.dart') {
        check(
          stdoutText.contains('Behavior checks passed'),
          'Did not exercise rejection after successful behavior validation.',
        );
      }
      for (final file in published) {
        check(
          equalBytes(file.readAsBytesSync(), before),
          'Replaced ${file.path}',
        );
      }
      final retained = stderrText
          .split('\n')
          .singleWhere(
            (line) => line.startsWith('Bootstrap work retained at: '),
          )
          .substring('Bootstrap work retained at: '.length);
      final snapshot = jsonDecode(
        File('$retained/inputs.json').readAsStringSync(),
      );
      final files = snapshot['files'] as Map;
      check(files.containsKey(changed.path), 'Missing original input snapshot');
      check(
        original == null
            ? files[changed.path] == null
            : equalBytes(base64Decode(files[changed.path] as String), original),
        'Lost the original input: $relative',
      );
      check(
        equalBytes(File('$retained/dartc-seed').readAsBytesSync(), before),
        'Lost the input seed',
      );
      if (original == null) {
        changed.deleteSync();
      } else {
        changed.writeAsBytesSync(original);
      }
    }
    passed = true;
    stdout.writeln('Bootstrap input checks passed.');
  } finally {
    if (passed) {
      work.deleteSync(recursive: true);
    } else {
      stderr.writeln('Bootstrap test work retained at: ${work.path}');
    }
  }
}
