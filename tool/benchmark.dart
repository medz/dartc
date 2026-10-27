import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'src/process.dart';
import 'src/program_benchmark.dart';

Future<String> sha256(List<int> bytes) async {
  final process = await Process.start(
    Platform.isMacOS ? '/usr/bin/shasum' : '/usr/bin/sha256sum',
    Platform.isMacOS ? ['-a', '256'] : [],
  );
  final output = process.stdout.transform(utf8.decoder).join();
  final errors = process.stderr.transform(utf8.decoder).join();
  process.stdin.add(bytes);
  await process.stdin.close();
  final code = await process.exitCode;
  if (code != 0) throw StateError(await errors);
  return (await output).split(' ').first.trim();
}

Future<String> sourceHash(String root) {
  final files = [
    for (final directory in ['bin', 'lib'])
      ...Directory('$root/$directory')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')),
  ]..sort((a, b) => a.path.compareTo(b.path));
  final bytes = BytesBuilder(copy: false);
  for (final file in files) {
    final content = file.readAsBytesSync();
    bytes.add(
      utf8.encode(
        '${file.path.substring(root.length + 1)}\x00${content.length}\x00',
      ),
    );
    bytes.add(content);
  }
  return sha256(bytes.takeBytes());
}

bool equalBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

num median(List<num> values) {
  values.sort();
  final middle = values.length ~/ 2;
  return values.length.isOdd
      ? values[middle]
      : (values[middle - 1] + values[middle]) / 2;
}

Future<void> main(List<String> args) async {
  final root = File.fromUri(Platform.script).parent.parent.absolute.path;
  if (args.isNotEmpty && args[0] == '--program') {
    await programBenchmark(args, root);
    return;
  }
  var seed = '$root/build/dartc-seed';
  final comparing = args.length == 3 && args[0] == '--compare';
  if (args.length == 2 && args[0] == '--seed') {
    seed = File(args[1]).absolute.path;
  } else if (args.isNotEmpty && !comparing) {
    stderr.writeln(
      'Usage: dart tool/benchmark.dart [--seed <native compiler>]\n'
      '       dart tool/benchmark.dart --compare <baseline-native> <candidate-native>\n'
      '       dart tool/benchmark.dart --program <entry> [--seed <native>] [--packages <config>]\n'
      '            [--input <relative-file>]... [--check-output <relative-file>]... -- [args...]',
    );
    exitCode = 64;
    return;
  }
  final outputs = <String, String>{};
  var cleanupTargets = false;
  Directory? measurementDirectory;
  try {
    if (!Platform.isMacOS && !Platform.isLinux) {
      throw StateError('The benchmark supports macOS and Linux.');
    }
    final inputs = comparing
        ? {
            'baseline': File(args[1]).absolute.path,
            'candidate': File(args[2]).absolute.path,
          }
        : {'seed': seed};
    for (final name in inputs.keys) {
      final file = File(inputs[name]!);
      if (!file.existsSync()) {
        throw StateError('Native compiler missing: ${file.path}.');
      }
      inputs[name] = file.resolveSymbolicLinksSync();
    }
    final build = Directory('$root/build')..createSync(recursive: true);
    measurementDirectory = build.createTempSync('benchmark-measure-');
    final sampleReports = [
      for (var index = 0; index < 16; index++)
        '${measurementDirectory.path}/sample-$index.json',
    ];
    final taskManifest = '${measurementDirectory.path}/inputs.json';
    final names = comparing
        ? ['baseline', 'candidate']
        : ['native', 'official'];
    final folders = <String, String>{};
    for (final name in names) {
      final directory = Directory('${measurementDirectory.path}/$name')
        ..createSync();
      folders[name] = directory.resolveSymbolicLinksSync();
      outputs[name] = '${folders[name]}/compiled-dartc';
    }
    final engines = comparing
        ? {...inputs}
        : {for (final name in names) name: '${folders[name]}/dartc-reference'};
    final result = File('${build.resolveSymbolicLinksSync()}/benchmark.json');
    final outputPaths = [
      if (!comparing) ...engines.values,
      ...outputs.values,
      result.path,
      taskManifest,
      ...sampleReports,
    ];
    for (final input in inputs.values) {
      for (final output in outputPaths) {
        if (input == output ||
            File(output).existsSync() &&
                FileSystemEntity.identicalSync(input, output)) {
          throw StateError(
            'Native compilers must differ from the benchmark output paths.',
          );
        }
      }
    }
    final inputHashes = {
      for (final entry in inputs.entries)
        entry.key: await sha256(File(entry.value).readAsBytesSync()),
    };
    final sdk = Platform.resolvedExecutable;
    final source = '$root/bin/dartc.dart';
    final standard = '$root/lib/src/runtime.dart';
    final sourceBefore = await sourceHash(root);
    final sampler = '$root/tool/src/measure.dart';
    final processHelper = '$root/tool/src/process.dart';
    final samplerHash = await sha256(File(sampler).readAsBytesSync());
    final processHash = await sha256(File(processHelper).readAsBytesSync());
    File(taskManifest).writeAsStringSync(
      jsonEncode({
        'source': source,
        'runtime': standard,
        'source_sha256': sourceBefore,
        'inputs': inputs,
        'input_sha256': inputHashes,
        'sampler_sha256': samplerHash,
        'process_helper_sha256': processHash,
      }),
    );
    var nextSample = 0;
    Future<Map<String, Object?>> measure(
      String executable,
      List<String> arguments, {
      bool isolated = true,
    }) async {
      final sampleReport = File(sampleReports[nextSample++]);
      final driver = await captureProcess(
        sdk,
        [
          sampler,
          '--report',
          sampleReport.path,
          '--',
          executable,
          ...arguments,
        ],
        workingDirectory: root,
        environment: {'LC_ALL': 'C', if (isolated) 'PATH': '/usr/bin:/bin'},
        includeParentEnvironment: !isolated,
        timeout: const Duration(seconds: 45),
      );
      if (driver.exitCode != 0 ||
          driver.timedOut ||
          driver.outputLimited ||
          driver.startError != null ||
          driver.captureError != null ||
          !sampleReport.existsSync()) {
        throw StateError(
          'Measurement driver failed; work: ${measurementDirectory!.path}',
        );
      }
      final data =
          jsonDecode(sampleReport.readAsStringSync()) as Map<String, dynamic>;
      final outcome = data['outcome'] as Map<String, dynamic>;
      if (outcome['exitCode'] != 0 ||
          outcome['timedOut'] != false ||
          outcome['outputLimited'] != false ||
          outcome['startError'] != null ||
          outcome['captureError'] != null) {
        throw StateError(
          'Native task failed; raw outcome: ${sampleReport.path}',
        );
      }
      final resource = data['measurement'] as Map<String, dynamic>?;
      num? milliseconds(String key) =>
          resource == null ? null : (resource[key] as num) / 1000;
      return {
        'wall_ms': milliseconds('wallMicroseconds'),
        'user_ms': milliseconds('userMicroseconds'),
        'system_ms': milliseconds('systemMicroseconds'),
        'cpu_ms': resource == null
            ? null
            : ((resource['userMicroseconds'] as num) +
                      (resource['systemMicroseconds'] as num)) /
                  1000,
        'rss_bytes': resource?['kernelPeakRssBytes'],
        'isolated': isolated,
        'sample_report': sampleReport.path,
        'measurement': resource,
        'measurement_issues': data['issues'],
        'outcome': outcome,
        'driver_outcome': driver.toJson(),
      };
    }

    final builds = <String, Map<String, Object?>>{};
    cleanupTargets = true;
    if (comparing) {
      stdout.writeln('Comparing existing native compilers:');
      for (final entry in engines.entries) {
        stdout.writeln('  ${entry.key}: ${entry.value}');
      }
    } else {
      seed = inputs['seed']!;
      final native = engines['native']!;
      final official = engines['official']!;
      stdout.writeln('Building native reference with $seed.');
      final nativeBuild = await measure(seed, [
        source,
        '-o',
        native,
        '--std',
        standard,
      ]);
      nativeBuild['path'] = native;
      nativeBuild['size_bytes'] = File(native).lengthSync();
      builds['native'] = nativeBuild;
      stdout.writeln(
        'Building official AOT reference with Dart SDK ${Platform.version.split(' ').first}.',
      );
      final officialBuild = await measure(sdk, [
        'compile',
        'exe',
        source,
        '-o',
        official,
      ], isolated: false);
      officialBuild['path'] = official;
      officialBuild['size_bytes'] = File(official).lengthSync();
      builds['official_aot_reference'] = officialBuild;
    }
    final engineHashes = comparing
        ? inputHashes
        : {
            for (final entry in engines.entries)
              entry.key: await sha256(File(entry.value).readAsBytesSync()),
          };
    final runs = <Map<String, Object?>>[];
    List<int>? expected;
    for (var iteration = 0; iteration <= 6; iteration++) {
      final order = iteration.isEven ? names : names.reversed;
      for (final name in order) {
        final output = File(outputs[name]!);
        if (output.existsSync()) output.deleteSync();
        final sample = await measure(engines[name]!, [
          source,
          '-o',
          outputs[name]!,
          '--std',
          standard,
        ]);
        if (!output.existsSync()) {
          throw StateError(
            '$name did not produce a compiler artifact; raw sample: ${sample['sample_report']}',
          );
        }
        final bytes = output.readAsBytesSync();
        expected ??= bytes;
        final matches = equalBytes(expected, bytes);
        final rawReport = File(sample['sample_report'] as String);
        final raw =
            jsonDecode(rawReport.readAsStringSync()) as Map<String, dynamic>;
        raw['parent_output_validation'] = {
          'size_bytes': bytes.length,
          'sha256': await sha256(bytes),
          'matches_prior_outputs': matches,
        };
        rawReport.writeAsStringSync(jsonEncode(raw));
        if (!matches) {
          throw StateError(
            '$name generated different native target bytes; raw sample: ${rawReport.path}',
          );
        }
        runs.add({
          'engine': name,
          'iteration': iteration,
          'warmup': iteration == 0,
          ...sample,
        });
      }
    }
    final medians = <String, Map<String, Object?>>{};
    for (final name in engines.keys) {
      final samples = runs
          .where(
            (sample) => sample['engine'] == name && sample['warmup'] == false,
          )
          .toList();
      num? sampleMedian(String key) {
        final values = [
          for (final sample in samples)
            if (sample[key] != null) sample[key] as num,
        ];
        return values.length == samples.length ? median(values) : null;
      }

      medians[name] = {
        for (final key in [
          'wall_ms',
          'user_ms',
          'system_ms',
          'cpu_ms',
          'rss_bytes',
        ])
          key: sampleMedian(key),
      };
    }
    final help = <ProcessOutcome>[];
    for (final name in names) {
      help.add(
        await captureProcess(
          outputs[name]!,
          ['--help'],
          workingDirectory: root,
          environment: const {'LC_ALL': 'C', 'PATH': '/usr/bin:/bin'},
          includeParentEnvironment: false,
          timeout: const Duration(seconds: 15),
        ),
      );
    }
    if (help.any(
          (item) =>
              item.exitCode != 0 ||
              item.timedOut ||
              item.outputLimited ||
              item.startError != null ||
              item.captureError != null,
        ) ||
        !equalBytes(help[0].stdoutBytes, help[1].stdoutBytes) ||
        !equalBytes(help[0].stderrBytes, help[1].stderrBytes)) {
      throw StateError('Generated compilers differ when executing --help.');
    }
    if (sourceBefore != await sourceHash(root)) {
      throw StateError('Compiler source changed during measurement.');
    }
    if (!comparing &&
        inputHashes['seed'] != await sha256(File(seed).readAsBytesSync())) {
      throw StateError('Native seed changed during measurement.');
    }
    for (final entry in engines.entries) {
      if (engineHashes[entry.key] !=
          await sha256(File(entry.value).readAsBytesSync())) {
        throw StateError('${entry.key} reference changed during measurement.');
      }
    }
    if (samplerHash != await sha256(File(sampler).readAsBytesSync()) ||
        processHash != await sha256(File(processHelper).readAsBytesSync())) {
      throw StateError('Measurement implementation changed during the run.');
    }
    final report = {
      'mode': comparing ? 'native_comparison' : 'official_reference',
      'comparison_scope': 'dartc_implementation_execution',
      'reference_role': comparing
          ? 'baseline_native_dartc'
          : 'sdk_aot_built_dartc',
      'sdk': {'path': sdk, 'version': Platform.version},
      'platform': Platform.operatingSystem,
      'source_sha256': sourceBefore,
      if (!comparing)
        'native_seed': {'path': seed, 'sha256': inputHashes['seed']},
      'task': {'source': source, 'runtime': standard},
      'build_samples': comparing ? 0 : 1,
      'build': builds,
      'compiler_paths': engines,
      'compiler_sha256': engineHashes,
      'output': {
        'size_bytes': expected!.length,
        'sha256': await sha256(expected),
        'all_bytes_identical': true,
        'help_behavior_identical': true,
      },
      'warmups': 1,
      'samples_per_engine': 6,
      'measurement_run_directory': measurementDirectory.path,
      'measurement_tool_sha256': samplerHash,
      'units': {
        'wall_ms': 'ms',
        'user_ms': 'ms',
        'system_ms': 'ms',
        'cpu_ms': 'ms',
        'rss_bytes': 'bytes',
      },
      'wall_scope': 'Native task spawn through exit/pipes; excludes Dart driver startup, FFI reads, hashes and JSON.',
      'cpu_scope': 'Waited child CPU, including waited descendants if present.',
      'rss_note': 'Kernel maximum child high-water; Darwin bytes, Linux KiB converted to bytes. Not simultaneous process-tree RSS. Unavailable metrics stay null, without time fallback.',
      'runs': runs,
      'medians': medians,
    };
    result.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(report)}\n',
    );
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(medians));
    stdout.writeln('Identical native target bytes; results: ${result.path}');
  } catch (error) {
    stderr.writeln(error);
    if (measurementDirectory != null) {
      stderr.writeln(
        'Measurement work retained at: ${measurementDirectory.path}',
      );
    }
    exitCode = 1;
  } finally {
    if (cleanupTargets) {
      for (final path in outputs.values) {
        final file = File(path);
        if (file.existsSync()) file.deleteSync();
      }
    }
  }
}
