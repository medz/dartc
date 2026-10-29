import 'dart:convert';
import 'dart:io';

import '../tool/src/process.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

bool equalBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

void completed(ProcessOutcome outcome, int expected) {
  check(
    outcome.exitCode == expected &&
        !outcome.timedOut &&
        !outcome.outputLimited &&
        outcome.startError == null &&
        outcome.captureError == null,
    jsonEncode(outcome.toJson()),
  );
}

Future<void> main(List<String> args) async {
  if (args.length != 2 || args[0] != '--compiler') {
    stderr.writeln(
      'Usage: dart test/program_benchmark_test.dart --compiler <native compiler>',
    );
    exitCode = 64;
    return;
  }
  final root = File.fromUri(Platform.script).parent.parent.path;
  final compilerInput = File(args[1]).absolute.resolveSymbolicLinksSync();
  final work = Directory(
    Directory.systemTemp
        .createTempSync('dartc-program-test-')
        .resolveSymbolicLinksSync(),
  );
  var passed = false;
  try {
    final compiler = File(compilerInput)
        .copySync('${work.path}/${r'native\seed'}')
        .path;
    // Give the command its own report/output paths, never the user's build/.
    final source = Directory('${work.path}/source')..createSync();
    final files = [
      'tool/benchmark.dart',
      'tool/src/program_benchmark.dart',
      'tool/src/measure.dart',
      'tool/src/process.dart',
      for (final file in Directory(
        '$root/lib',
      ).listSync(recursive: true).whereType<File>())
        if (file.path.endsWith('.dart')) file.path.substring(root.length + 1),
    ];
    for (final relative in files) {
      final destination = File('${source.path}/$relative');
      destination.parent.createSync(recursive: true);
      File('$root/$relative').copySync(destination.path);
    }
    final app = Directory('${work.path}/app task')..createSync();
    Directory('${app.path}/actual').createSync();
    Directory('${app.path}/pkg/lib/sub').createSync(recursive: true);
    Directory('${app.path}/data').createSync();
    final fixture = <String, String>{
      'actual/main.dart': '''
import 'package:task/value.dart';
import 'dependency.dart';
import 'present.dart' if (dart.library.html) 'absent.dart';
import '../source/lib/src/host.dart' as host;
void main(List<String> args) {
  final text = host.hostRead(args[0]);
  host.hostWrite(args[1], <int>[text.length, marker(), 255, 0]);
  print(label() + ':' + dependency().toString() + ':' + present().toString() + ':' + text);
}
''',
      // These relative URIs belong to config-link.json, not actual/config.json.
      'actual/config.json': jsonEncode({
        'configVersion': 2,
        'packages': [
          {
            'name': 'task',
            'rootUri': 'pkg/',
            'packageUri': 'lib/',
            'languageVersion': '3.13',
          },
        ],
      }),
      'dependency.dart': 'int dependency() => 7;\n',
      'present.dart': 'int present() => 11;\n',
      'pkg/lib/sub/middle.dart': "export '../../shared.dart';\n",
      'pkg/lib/value.dart':
          "export 'fallback.dart' if (dart.library.io) 'chosen.dart';\n",
      'pkg/lib/fallback.dart': "import 'sub/middle.dart';\nString label() => shared;\nint marker() => 65;\n",
      'pkg/lib/chosen.dart': "import 'sub/middle.dart';\nString label() => shared;\nint marker() => 65;\n",
      'pkg/lib/shared.dart': "const String shared = 'choice';\n",
      'data/input.txt': '你好🙂\n',
      'exit17.dart': '''
import '../source/lib/src/host.dart' as host;
void main() { print('before'); host.hostExit(17); }
''',
    };
    for (final item in fixture.entries) {
      File('${app.path}/${item.key}').writeAsStringSync(item.value);
    }
    Link('${app.path}/entry-link.dart').createSync('actual/main.dart');
    Link('${app.path}/config-link.json').createSync('actual/config.json');
    Link('${work.path}/source-link').createSync('source');
    final command = '${work.path}/source-link/tool/benchmark.dart';
    final taskArguments = [
      '--program',
      'entry-link.dart',
      '--packages',
      'config-link.json',
      '--seed',
      compiler,
      '--input',
      'data/input.txt',
      '--check-output',
      'result.bin',
      '--',
      'data/input.txt',
      'result.bin',
    ];
    Future<ProcessOutcome> run(List<String> arguments) => captureProcess(
      Platform.resolvedExecutable,
      [command, ...arguments],
      workingDirectory: app.path,
      environment: const {'PATH': '/usr/bin:/bin', 'LC_ALL': 'C', 'CI': 'true'},
      includeParentEnvironment: false,
      timeout: const Duration(minutes: 2),
    );
    completed(await run(taskArguments), 0);
    final report = File('${source.path}/build/program-benchmark.json');
    final accepted = report.readAsBytesSync();
    final result = jsonDecode(utf8.decode(accepted)) as Map<String, dynamic>;
    check(result['same_program_behavior'] == true, 'positive task rejected');
    check(
      RegExp(r'^[0-9a-f]{64}$')
          .hasMatch(result['native_compiler']['sha256'] as String),
      'escaped compiler filename produced an invalid digest',
    );
    final task = result['task'] as Map<String, dynamic>;
    check(task['entry'] == '${app.path}/entry-link.dart', 'entry URI changed');
    check(
      task['packages'] == '${app.path}/config-link.json',
      'package URI changed',
    );
    final rounds = result['rounds'] as List<dynamic>;
    check(rounds.length == 5, 'expected warmup and four paired samples');
    for (final round in rounds.cast<Map<String, dynamic>>()) {
      for (final lane in ['official', 'native']) {
        final compile = round['compile'][lane] as Map<String, dynamic>;
        final execution = round['run'][lane] as Map<String, dynamic>;
        final outcome = execution['outcome'] as Map<String, dynamic>;
        check(outcome['exitCode'] == 0, 'task did not succeed');
        check(
          utf8.decode(base64Decode(outcome['stdoutBase64'] as String)) ==
              'choice:7:11:你好🙂\n\n',
          'program stdout',
        );
        check(outcome['stderrBase64'] == '', 'program stderr');
        check(
          execution['artifact_sha256_after'] == compile['artifact_sha256'],
          'executed image changed',
        );
        final output = round['output_files'][lane]['result.bin'] as Map;
        check(
          equalBytes(File(output['snapshot'] as String).readAsBytesSync(), [
            5,
            65,
            255,
            0,
          ]),
          'declared file output',
        );
      }
    }
    for (final item in fixture.entries) {
      check(
        equalBytes(
          File('${app.path}/${item.key}').readAsBytesSync(),
          utf8.encode(item.value),
        ),
        'source/data changed: ${item.key}',
      );
    }
    check(
      !File('${app.path}/result.bin').existsSync(),
      'command wrote into the original cwd',
    );

    // Same stdout/exit, differing file bytes: reject before report publication.
    File('${app.path}/pkg/lib/chosen.dart').writeAsStringSync(
      "import 'sub/middle.dart';\nString label() => shared;\nint marker() => 66;\n",
    );
    final fileFailure = await run(taskArguments);
    completed(fileFailure, 1);
    check(
      fileFailure.stderr.contains('Output file result.bin differs'),
      'file mismatch was not detected: ${fileFailure.stderr}',
    );
    check(
      equalBytes(report.readAsBytesSync(), accepted),
      'file mismatch replaced the accepted report',
    );

    // Both implementations exit 17; this mode has no failure-outcome contract.
    final failingNative = '${work.path}/exit17-native';
    completed(
      await captureProcess(
        compiler,
        [
          '${app.path}/exit17.dart',
          '--std',
          '${source.path}/lib/src/runtime.dart',
          '-o',
          failingNative,
        ],
        environment: const {'PATH': '/usr/bin:/bin', 'LC_ALL': 'C'},
        includeParentEnvironment: false,
      ),
      0,
    );
    final nativeExit = await captureProcess(
      failingNative,
      const [],
      environment: const {'PATH': '/usr/bin:/bin', 'LC_ALL': 'C'},
      includeParentEnvironment: false,
    );
    completed(nativeExit, 17);
    check(
      nativeExit.stdout == 'before\n' && nativeExit.stderr == '',
      'native failure behavior',
    );
    final exitFailure = await run([
      '--program',
      'exit17.dart',
      '--seed',
      compiler,
    ]);
    completed(exitFailure, 1);
    check(
      exitFailure.stderr.contains('program exited unsuccessfully'),
      'nonzero task was not rejected: ${exitFailure.stderr}',
    );
    check(
      equalBytes(report.readAsBytesSync(), accepted),
      'nonzero task replaced the accepted report',
    );

    // Compare two native runtimes with the SDK as the behavior reference.
    // The native-only package branch calls an ordinary function in each core.
    File('${app.path}/compare.dart').writeAsStringSync('''
import 'package:task/value.dart';
void main() { print(label() + ':' + marker().toString()); }
''');
    File('${app.path}/pkg/lib/chosen.dart')
        .writeAsStringSync(fixture['pkg/lib/chosen.dart']!);
    File('${app.path}/pkg/lib/fallback.dart').writeAsStringSync(
      "import 'sub/middle.dart';\nString label() => shared;\nint marker() => benchmarkMarker();\n",
    );
    final core = File('${source.path}/lib/src/std/core.dart');
    final originalCore = core.readAsStringSync();
    core.writeAsStringSync('$originalCore\nint benchmarkMarker() => 65;\n');
    final baseline = Directory('${work.path}/baseline lib');
    for (final file in Directory(
      '${source.path}/lib',
    ).listSync(recursive: true).whereType<File>()) {
      final relative = file.path.substring('${source.path}/lib/'.length);
      final destination = File('${baseline.path}/$relative');
      destination.parent.createSync(recursive: true);
      file.copySync(destination.path);
    }
    final comparisonArguments = [
      '--program',
      'compare.dart',
      '--packages',
      'config-link.json',
      '--compare',
      compiler,
      compiler,
      '--baseline-std',
      '${baseline.path}/src/runtime.dart',
      '--std',
      '${source.path}/lib/src/runtime.dart',
    ];
    completed(await run(comparisonArguments), 0);
    final comparisonAccepted = report.readAsBytesSync();
    final comparison = jsonDecode(utf8.decode(comparisonAccepted)) as Map;
    check(comparison['mode'] == 'program_native_comparison', 'comparison mode');
    check(comparison['abi'] is String, 'missing measurement ABI');
    for (final lane in ['official', 'baseline', 'candidate']) {
      check(comparison['medians'][lane] is Map, 'missing $lane measurements');
      for (final round in comparison['rounds'] as List) {
        final outcome = round['run'][lane]['outcome'] as Map;
        check(outcome['exitCode'] == 0, '$lane execution failed');
        check(
          utf8.decode(base64Decode(outcome['stdoutBase64'] as String)) ==
              'choice:65\n',
          '$lane output',
        );
        check(outcome['stderrBase64'] == '', '$lane stderr');
      }
    }
    for (final item in {
      'baseline': '${baseline.path}/src/runtime.dart',
      'candidate': '${source.path}/lib/src/runtime.dart',
    }.entries) {
      check(
        comparison['native_compilers'][item.key]['runtime'] == item.value,
        '${item.key} runtime identity',
      );
      check(
        (comparison['task']['native_source_uris_by_compiler'][item.key] as List)
            .contains(File(item.value).uri.toString()),
        '${item.key} runtime dependencies',
      );
    }
    // A candidate-only behavior change must leave the accepted report intact.
    core.writeAsStringSync('$originalCore\nint benchmarkMarker() => 66;\n');
    final comparisonFailure = await run(comparisonArguments);
    completed(comparisonFailure, 1);
    check(
      comparisonFailure.stderr.contains('Program behavior differs'),
      'candidate mismatch was not detected: ${comparisonFailure.stderr}',
    );
    check(
      equalBytes(report.readAsBytesSync(), comparisonAccepted),
      'candidate mismatch replaced the accepted report',
    );
    for (final invalidOptions in [
      ['--compare', compiler],
      ['--compare', compiler, compiler, '--seed', compiler],
      ['--baseline-std', '${baseline.path}/src/runtime.dart'],
    ]) {
      completed(
        await run(['--program', 'compare.dart', ...invalidOptions]),
        64,
      );
    }
    passed = true;
    stdout.writeln('Program benchmark integration passed.');
  } finally {
    if (passed) {
      work.deleteSync(recursive: true);
    } else {
      stderr.writeln('Program benchmark work retained at: ${work.path}');
    }
  }
}
