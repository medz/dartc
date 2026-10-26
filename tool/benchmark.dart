import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

int? residentBytes(String output) {
  final match = RegExp(
    Platform.isMacOS
        ? r'(\d+)\s+maximum resident set size'
        : r'Maximum resident set size \(kbytes\):\s*(\d+)',
  ).firstMatch(output);
  if (match == null) return null;
  return int.parse(match[1]!) * (Platform.isMacOS ? 1 : 1024);
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
  var seed = '$root/build/dartc-seed';
  final comparing = args.length == 3 && args[0] == '--compare';
  if (args.length == 2 && args[0] == '--seed') {
    seed = File(args[1]).absolute.path;
  } else if (args.isNotEmpty && !comparing) {
    stderr.writeln(
      'Usage: dart tool/benchmark.dart [--seed <native compiler>]\n'
      '       dart tool/benchmark.dart --compare <baseline-native> <candidate-native>',
    );
    exitCode = 64;
    return;
  }
  final outputs = <String, String>{};
  var cleanupTargets = false;
  try {
    if (!comparing && Platform.version.split(' ').first != '3.13.5') {
      throw StateError('Run the reference benchmark with Dart SDK 3.13.5.');
    }
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
    final names = comparing
        ? ['baseline', 'candidate']
        : ['native', 'official'];
    final folders = <String, String>{};
    for (final name in names) {
      final directory = Directory('${build.path}/benchmark-$name')
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
    final timeOptions = Platform.isMacOS ? ['-l'] : ['-v'];
    final timeExists = File('/usr/bin/time').existsSync();
    final timeProbe = timeExists
        ? Process.runSync(
            '/usr/bin/time',
            [...timeOptions, '/usr/bin/true'],
            environment: {'LC_ALL': 'C'},
          )
        : null;
    final hasRss =
        timeProbe != null &&
        timeProbe.exitCode == 0 &&
        residentBytes('${timeProbe.stderr}') != null;
    final rssNote = hasRss
        ? 'Darwin bytes; Linux KiB multiplied by 1024.'
        : '/usr/bin/time RSS unavailable: ${timeProbe?.stderr ?? 'not installed'}';

    Map<String, Object?> measure(
      String executable,
      List<String> arguments, {
      bool isolated = true,
    }) {
      final watch = Stopwatch()..start();
      final result = Process.runSync(
        hasRss ? '/usr/bin/time' : executable,
        hasRss ? [...timeOptions, executable, ...arguments] : arguments,
        workingDirectory: root,
        environment: {'LC_ALL': 'C', if (isolated) 'PATH': '/usr/bin:/bin'},
        includeParentEnvironment: !isolated,
      );
      watch.stop();
      if (result.exitCode != 0) {
        throw ProcessException(
          executable,
          arguments,
          '${result.stdout}${result.stderr}',
          result.exitCode,
        );
      }
      return {
        'wall_ms': watch.elapsedMicroseconds / 1000,
        'rss_bytes': hasRss ? residentBytes('${result.stderr}') : null,
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
      final nativeBuild = measure(seed, [
        source,
        '-o',
        native,
        '--std',
        standard,
      ]);
      nativeBuild['path'] = native;
      nativeBuild['size_bytes'] = File(native).lengthSync();
      builds['native'] = nativeBuild;
      stdout.writeln('Building official AOT reference with Dart SDK 3.13.5.');
      final officialBuild = measure(sdk, [
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
        final sample = measure(engines[name]!, [
          source,
          '-o',
          outputs[name]!,
          '--std',
          standard,
        ]);
        final bytes = File(outputs[name]!).readAsBytesSync();
        expected ??= bytes;
        if (!equalBytes(expected, bytes)) {
          throw StateError('$name generated different native target bytes.');
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
      medians[name] = {
        'wall_ms': median([
          for (final sample in samples) sample['wall_ms'] as num,
        ]),
        'rss_bytes': hasRss
            ? median([for (final sample in samples) sample['rss_bytes'] as num])
            : null,
      };
    }
    final help = [
      for (final name in names)
        Process.runSync(
          outputs[name]!,
          ['--help'],
          environment: {'LC_ALL': 'C', 'PATH': '/usr/bin:/bin'},
          includeParentEnvironment: false,
        ),
    ];
    if (help[0].exitCode != 0 ||
        help[1].exitCode != 0 ||
        help[0].stdout != help[1].stdout ||
        help[0].stderr != help[1].stderr) {
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
    final report = {
      'mode': comparing ? 'native_comparison' : 'official_reference',
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
      'rss_note': rssNote.trim(),
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
