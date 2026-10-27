import 'dart:convert';
import 'dart:io';

import '../tool/src/process.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void completed(ProcessOutcome result) {
  check(
    result.exitCode == 0 &&
        !result.timedOut &&
        !result.outputLimited &&
        result.startError == null &&
        result.captureError == null,
    jsonEncode(result.toJson()),
  );
}

Future<void> main(List<String> args) async {
  if (args.length != 4 || args[0] != '--compiler' || args[2] != '--std') {
    stderr.writeln(
      'Usage: dart test/measure_test.dart --compiler <native compiler> --std <runtime.dart>',
    );
    exitCode = 64;
    return;
  }
  final root = File.fromUri(Platform.script).parent.parent.path;
  final compiler = File(args[1]).absolute.path;
  final standard = File(args[3]).absolute;
  final work = Directory.systemTemp.createTempSync('dartc-measure-test-');
  var passed = false;
  try {
    final source = File('${work.path}/task.dart');
    final host = standard.parent.uri.resolve('host.dart');
    source.writeAsStringSync(
      "import '$host' as host;\n"
      "void main(List<String> args) {\n"
      "  if (args.isNotEmpty) host.hostExit(17);\n"
      "  print('sampler ok');\n"
      "}\n",
    );
    final native = '${work.path}/task';
    completed(
      await captureProcess(
        compiler,
        [source.path, '--std', standard.path, '-o', native],
        workingDirectory: work.path,
        environment: const {'PATH': '/usr/bin:/bin'},
        includeParentEnvironment: false,
      ),
    );
    final samples = <Map<String, dynamic>>[];
    for (var index = 0; index < 3; index++) {
      final report = File('${work.path}/sample-$index.json');
      completed(
        await captureProcess(
          Platform.resolvedExecutable,
          [
            '$root/tool/src/measure.dart',
            '--report',
            report.path,
            '--',
            native,
            if (index == 1) 'fail',
          ],
          workingDirectory: work.path,
          environment: const {'PATH': '/usr/bin:/bin'},
          includeParentEnvironment: false,
        ),
      );
      final sample =
          jsonDecode(report.readAsStringSync()) as Map<String, dynamic>;
      check(sample['priorChildrenZero'] == true, 'sample was not fresh');
      final outcome = sample['outcome'] as Map<String, dynamic>;
      check(outcome['exitCode'] == (index == 1 ? 17 : 0), 'child exit code');
      check(
        utf8.decode(base64Decode(outcome['stdoutBase64'] as String)) ==
            (index == 1 ? '' : 'sampler ok\n'),
        'native output',
      );
      if (index == 1) {
        check(sample['measurement'] == null, 'failed task produced a sample');
        check((sample['issues'] as List).isNotEmpty, 'missing failure reason');
      } else {
        final measured = sample['measurement'] as Map<String, dynamic>;
        check(
          (measured['wallMicroseconds'] as int) > 0 &&
              (measured['userMicroseconds'] as int) >= 0 &&
              (measured['systemMicroseconds'] as int) >= 0 &&
              (measured['kernelPeakRssBytes'] as int) > 0,
          'invalid resource measurement',
        );
      }
      samples.add(sample);
    }
    check(
      samples.map((sample) => sample['driverPid']).toSet().length == 3,
      'samples reused a driver',
    );
    passed = true;
    stdout.writeln('Native resource samples passed.');
  } finally {
    if (passed) {
      work.deleteSync(recursive: true);
    } else {
      stderr.writeln('Measurement work retained at: ${work.path}');
    }
  }
}
