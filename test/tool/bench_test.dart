import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

void main() {
  final bench = File('tool/bench.dart').absolute.path;
  final fixture = File('test/tool/fixtures/bench_compiler.sh').absolute;
  final sourceCompiler = File('test/tool/fixtures/bench_source_compiler.dart')
      .absolute;
  final builder = File('test/tool/fixtures/bench_builder.dart').absolute;
  final packages = File('.dart_tool/package_config.json').absolute.path;
  final source = File('tool/bench/fixtures/hello.dart').absolute;
  late Directory workspace;
  late File compiler;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('dartc-bench-test-');
    await Directory('${workspace.path}/.git').create();
    compiler = await fixture.copy('${workspace.path}/compiler');
    final input = File('${workspace.path}/tool/bench/fixtures/hello.dart');
    await input.parent.create(recursive: true);
    await source.copy(input.path);
    final chmod = await Process.run('chmod', ['+x', compiler.path]);
    expect(chmod.exitCode, 0, reason: '${chmod.stderr}');
  });

  tearDown(() async {
    await workspace.delete(recursive: true);
  });

  Future<ProcessResult> run({
    String? baseline,
    String output = 'report.json',
    String padding = '',
    String delay = '0',
    int maxTimeGrowth = 1000000,
    bool externalCompiler = true,
    List<String> arguments = const [],
    Map<String, String> environment = const {},
  }) => Process.run(
    Platform.resolvedExecutable,
    [
      '--packages=$packages',
      bench,
      '--only=hello',
      if (externalCompiler) '--compiler=${compiler.path}',
      '--run-repeats=1',
      '--output=$output',
      '--max-time-growth=$maxTimeGrowth',
      if (baseline != null) '--baseline=$baseline',
      ...arguments,
    ],
    workingDirectory: workspace.path,
    environment: {
      'BENCH_TEST_PADDING': padding,
      'BENCH_TEST_DELAY': delay,
      ...environment,
    },
  );

  Future<Map<String, dynamic>> recordBaseline() async {
    final result = await run(output: 'baseline.json');
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    return jsonDecode(
      await File('${workspace.path}/baseline.json').readAsString(),
    ) as Map<String, dynamic>;
  }

  Future<void> prepareSource() async {
    final script = File('${workspace.path}/bin/dartc.dart');
    await script.parent.create(recursive: true);
    await sourceCompiler.copy(script.path);
    await Directory('${workspace.path}/lib').create();
    final version = File('${workspace.path}/sdk/std/version');
    await version.parent.create(recursive: true);
    await version.writeAsString('fixture-sdk\n');
    await File('${workspace.path}/sdk/std/revision')
        .writeAsString('fixture-revision\n');
  }

  test('a report can be reused as a baseline with a displayed delta', () async {
    await recordBaseline();
    final result = await run(baseline: 'baseline.json');
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, matches(r'ok \([+-]\d+ us\)'));
  });

  test('a larger output fails comparison against the emitted report', () async {
    final baseline = await recordBaseline();
    final result = await run(baseline: 'baseline.json', padding: 'x' * 4096);
    final report = jsonDecode(
      await File('${workspace.path}/report.json').readAsString(),
    ) as Map<String, dynamic>;
    expect(
      report['fixtures']['hello']['bytes'],
      greaterThan(baseline['fixtures']['hello']['bytes']),
    );
    expect(result.exitCode, 1, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, contains('REGRESSION'));
  });

  test('elapsed-time growth also fails report comparison', () async {
    final baseline = await recordBaseline();
    baseline['fixtures']['hello']['elapsedUs'] = 1;
    await File('${workspace.path}/baseline.json')
        .writeAsString(jsonEncode(baseline));
    final result = await run(
      baseline: 'baseline.json',
      delay: '0.1',
      maxTimeGrowth: 10,
    );
    expect(result.exitCode, 1, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, contains('REGRESSION'));
  });

  Future<Map<String, dynamic>> report() async =>
      jsonDecode(await File('${workspace.path}/report.json').readAsString())
          as Map<String, dynamic>;

  test(
    'both compilation pipes drain completely with bounded report tails',
    () async {
      final result = await run(environment: {'BENCH_TEST_LOGS': 'long'});
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final row = (await report())['fixtures']['hello'];
      expect(row['outputComplete'], isTrue);
      expect(row['stdout'], endsWith('stdout-final-marker\n'));
      expect(row['stderr'], endsWith('stderr-final-marker\n'));
      expect(row['stdoutTruncated'], isTrue);
      expect(row['stderrTruncated'], isTrue);
      expect((row['stdout'] as String).length, lessThanOrEqualTo(4000));
      expect((row['stderr'] as String).length, lessThanOrEqualTo(4000));
    },
  );

  test(
    'compiler timeout records the real killed exit and partial diagnostics',
    () async {
      final result = await run(
        arguments: ['--timeout=1'],
        environment: {'BENCH_TEST_COMPILE_MODE': 'hang'},
      );
      expect(result.exitCode, 1);
      final row = (await report())['fixtures']['hello'];
      expect(row['timedOut'], isTrue);
      expect(row['exitCode'], -9);
      expect(row['stderr'], contains('before timeout'));
      expect(row['outputComplete'], isFalse);
      expect(row['runs'], isEmpty);
    },
  );

  for (final mode in ['hang', 'child-hang']) {
    test('output timeout bounds $mode execution and records failure', () async {
      final result = await run(
        arguments: ['--run-timeout=1'],
        environment: {'BENCH_TEST_RUN_MODE': mode},
      );
      expect(result.exitCode, 1);
      final row = (await report())['fixtures']['hello'];
      expect(row['exitCode'], 0);
      expect(row['failed'], isTrue);
      expect(row['runs'], hasLength(1));
      final measured = row['runs'][0];
      expect(measured['timedOut'], isTrue);
      expect(measured['exitCode'], -9);
      expect(measured['elapsedUs'], greaterThanOrEqualTo(1000000));
      if (mode == 'child-hang') {
        final pid = int.parse(
          await File('${workspace.path}/output-child').readAsString(),
        );
        final state = await Process.run('ps', ['-o', 'stat=', '-p', '$pid']);
        expect(
          state.exitCode != 0 || '${state.stdout}'.trim().startsWith('Z'),
          isTrue,
          reason: 'The timed-out descendant must not keep running.',
        );
      }
    });
  }

  test(
    'compiler failure preserves its exit and cannot reuse an old output',
    () async {
      await recordBaseline();
      await File('${workspace.path}/output-ran').delete();
      final result = await run(
        environment: {'BENCH_TEST_COMPILE_MODE': 'fail'},
      );
      expect(result.exitCode, 1);
      final row = (await report())['fixtures']['hello'];
      expect(row['exitCode'], 23);
      expect(row['stderr'], contains('compile failure'));
      expect(row['artifact'], isNull);
      expect(row['runs'], isEmpty);
      expect(File('${workspace.path}/output-ran').existsSync(), isFalse);
    },
  );

  test(
    'a missing fresh output fails even after a previous successful run',
    () async {
      await recordBaseline();
      await File('${workspace.path}/output-ran').delete();
      final result = await run(
        environment: {'BENCH_TEST_COMPILE_MODE': 'no-output'},
      );
      expect(result.exitCode, 1);
      final row = (await report())['fixtures']['hello'];
      expect(row['exitCode'], 0);
      expect(row['failed'], isTrue);
      expect(row['failure'], contains('without producing'));
      expect(File('${workspace.path}/output-ran').existsSync(), isFalse);
    },
  );

  for (final mode in ['fail', 'wrong']) {
    test('a $mode output stops repetition and cannot report success', () async {
      final result = await run(
        arguments: ['--run-repeats=3'],
        environment: {'BENCH_TEST_RUN_MODE': mode},
      );
      expect(result.exitCode, 1);
      final row = (await report())['fixtures']['hello'];
      expect(row['runs'], hasLength(1));
      expect(row['runs'][0]['exitCode'], mode == 'fail' ? 17 : 0);
      expect(row['runs'][0]['matched'], mode == 'fail');
      if (mode == 'fail') {
        expect(row['runs'][0]['stderr'], contains('run failure'));
      }
    });
  }

  test(
    'report identities describe the measured binary, workload and output',
    () async {
      final result = await run();
      expect(result.exitCode, 0);
      final document = await report();
      final binary = document['compiler'];
      final row = document['fixtures']['hello'];
      expect(document['format'], 2);
      expect(
        binary['sha256'],
        sha256.convert(await compiler.readAsBytes()).toString(),
      );
      expect(binary['mode'], 'external');
      expect(
        binary['source'],
        isNull,
        reason: 'An external binary has no proven source revision.',
      );
      expect(
        row['source']['sha256'],
        sha256.convert(await source.readAsBytes()).toString(),
      );
      expect(
        row['artifact']['sha256'],
        sha256
            .convert(
              await File(row['artifact']['path'] as String).readAsBytes(),
            )
            .toString(),
      );
      expect(row['elapsedUs'], greaterThan(0));
      expect(row['runMedianUs'], greaterThan(0));
      expect(row['command'], containsAll(['--kind', 'exe', '--target']));
      expect(row['peakRssKiB'], isNull);
      expect(document['rssSampling']['intervalUs'], 100000);
      expect(document['rssSampling']['scope'], 'direct compiler process');
      expect(document['configuration']['runRepeats'], 1);
      expect(document['inputChanges'], isEmpty);
      expect(document['environmentSha256'], matches(r'^[a-f0-9]{64}$'));
    },
  );

  test(
    'source mode fingerprints the actual compiler and SDK input tree',
    () async {
      await prepareSource();
      final version = File('${workspace.path}/sdk/std/version');
      final first = await run(externalCompiler: false);
      expect(first.exitCode, 0, reason: '${first.stdout}\n${first.stderr}');
      final firstSource = (await report())['compiler']['source'];
      expect(firstSource['sdk']['version'], 'fixture-sdk');
      expect(firstSource['sdk']['revision'], 'fixture-revision');
      expect(firstSource['sha256'], matches(r'^[a-f0-9]{64}$'));
      expect(firstSource['sdk']['sha256'], matches(r'^[a-f0-9]{64}$'));
      await version.writeAsString('changed-sdk\n');
      final second = await run(externalCompiler: false);
      expect(second.exitCode, 0, reason: '${second.stdout}\n${second.stderr}');
      final secondSource = (await report())['compiler']['source'];
      expect(secondSource['sha256'], isNot(firstSource['sha256']));
      expect(
        secondSource['sdk']['sha256'],
        isNot(firstSource['sdk']['sha256']),
      );
    },
  );

  test(
    'built provenance includes the producer and its source dependencies',
    () async {
      await prepareSource();
      final script = await builder.copy('${workspace.path}/tool/build.dart');
      final dependency = File('${workspace.path}/tool/src/compiler_build.dart');
      await dependency.parent.create(recursive: true);
      await dependency.writeAsString('// builder dependency fixture\n');
      final original = await run(
        externalCompiler: false,
        arguments: ['--build'],
      );
      expect(
        original.exitCode,
        0,
        reason: '${original.stdout}\n${original.stderr}',
      );
      var previous = (await report())['compiler'];
      expect(previous['mode'], 'built');
      for (final input in [script, dependency]) {
        await input.writeAsString(
          '// changed builder input\n',
          mode: FileMode.append,
        );
        final result = await run(
          externalCompiler: false,
          arguments: ['--build'],
        );
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        final current = (await report())['compiler'];
        expect(current['sha256'], previous['sha256']);
        expect(
          current['source']['sha256'],
          isNot(previous['source']['sha256']),
        );
        previous = current;
      }
    },
  );

  test(
    'an invalid lock parent fails immediately with its filesystem cause',
    () async {
      await Directory('${workspace.path}/.git').delete();
      await File('${workspace.path}/.git').writeAsString('not a git directory');
      final process = await Process.start(Platform.resolvedExecutable, [
        '--packages=$packages',
        bench,
        '--only=hello',
        '--compiler=${compiler.path}',
        '--output=report.json',
      ], workingDirectory: workspace.path);
      final out = process.stdout.transform(utf8.decoder).join();
      final err = process.stderr.transform(utf8.decoder).join();
      var timedOut = false;
      final code = await process.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          timedOut = true;
          process.kill(ProcessSignal.sigkill);
          return process.exitCode;
        },
      );
      final output = await out, error = await err;
      expect(timedOut, isFalse, reason: '$output\n$error');
      expect(code, isNot(0));
      expect(error, contains('FileSystemException'));
      expect(error, contains('dartc-bench.lock'));
      expect(error, isNot(contains('Another dartc benchmark')));
      expect(File('${workspace.path}/compiler-ran').existsSync(), isFalse);
    },
  );

  for (final input in ['compiler', 'workload']) {
    test('changing $input during measurement invalidates the report', () async {
      final result = await run(environment: {'BENCH_TEST_MUTATE': input});
      expect(result.exitCode, 1);
      expect((await report())['inputChanges'], isNotEmpty);
      expect(result.stderr, contains('inputs changed during measurement'));
    });
  }

  test(
    'an output that cannot start records an error and no invented exit',
    () async {
      final result = await run(
        environment: {'BENCH_TEST_COMPILE_MODE': 'bad-output'},
      );
      expect(result.exitCode, 1);
      final row = (await report())['fixtures']['hello'];
      expect(row['runs'], hasLength(1));
      expect(row['runs'][0]['exitCode'], isNull);
      expect(row['runs'][0]['error'], isNotEmpty);
      expect(row['failed'], isTrue);
    },
  );

  test(
    'cross-generation requires compile-only and records no execution',
    () async {
      final target = Platform.isMacOS ? 'linux-arm64' : 'macos-arm64';
      final refused = await run(arguments: ['--target=$target']);
      expect(refused.exitCode, isNot(0));
      expect(File('${workspace.path}/compiler-ran').existsSync(), isFalse);
      final generated = await run(
        arguments: ['--target=$target', '--compile-only'],
      );
      expect(generated.exitCode, 0, reason: '${generated.stderr}');
      final row = (await report())['fixtures']['hello'];
      expect(row['runs'], isEmpty);
      expect(row['runMedianUs'], isNull);
      expect(File('${workspace.path}/output-ran').existsSync(), isFalse);
    },
  );

  for (final argument in [
    '--only=missing',
    '--timeout=0',
    '--run-timeout=0',
    '--max-time-growth=NaN',
  ]) {
    test('invalid $argument is rejected before starting a compiler', () async {
      final result = await run(arguments: [argument]);
      expect(result.exitCode, isNot(0));
      expect(File('${workspace.path}/compiler-ran').existsSync(), isFalse);
    });
  }

  for (final (name, invalidate)
      in <(String, void Function(Map<String, dynamic>))>[
        ('different target', (report) => report['target'] = 'different-target'),
        (
          'source compiler mode',
          (report) => report['compiler']['mode'] = 'source',
        ),
        (
          'built compiler mode',
          (report) => report['compiler']['mode'] = 'built',
        ),
        (
          'different host target',
          (report) => report['host']['target'] = 'different',
        ),
        (
          'different host OS',
          (report) => report['host']['operatingSystemVersion'] = 'different',
        ),
        (
          'different host Dart',
          (report) => report['host']['dart'] = 'different',
        ),
        (
          'different execution count',
          (report) => report['configuration']['runRepeats'] = 2,
        ),
        (
          'changed workload',
          (report) =>
              report['fixtures']['hello']['source']['sha256'] = 'different',
        ),
        (
          'failed run',
          (report) => report['fixtures']['hello']['runs'][0]['exitCode'] = 4,
        ),
        ('missing fixtures', (report) => report.remove('fixtures')),
        (
          'missing selected fixture',
          (report) => report['fixtures'].remove('hello'),
        ),
        (
          'invalid metric',
          (report) => report['fixtures']['hello']['bytes'] = 'bad',
        ),
        (
          'failed fixture',
          (report) => report['fixtures']['hello']['exitCode'] = 1,
        ),
      ]) {
    test('a baseline with $name is rejected before compilation', () async {
      final baseline = await recordBaseline();
      invalidate(baseline);
      await File('${workspace.path}/baseline.json')
          .writeAsString(jsonEncode(baseline));
      final marker = File('${workspace.path}/compiler-ran');
      await marker.delete();
      final result = await run(baseline: 'baseline.json');
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('Invalid benchmark baseline'));
      expect(marker.existsSync(), isFalse);
      expect(File('${workspace.path}/report.json').existsSync(), isFalse);
    });
  }
}
