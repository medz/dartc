import 'dart:convert';
import 'dart:io';

import '../../lib/src/ast.dart';
import '../../lib/src/driver/packages.dart';
import '../../lib/src/package_config.dart';
import '../../lib/src/parser.dart';
import '../../lib/src/scanner.dart';
import '../../lib/src/source.dart';
import '../../lib/src/source_uri.dart';
import 'process.dart';

String _file(String path, [Map<String, String>? aliases]) {
  final absolute = File(path).absolute.path;
  final resolved = File(absolute).resolveSymbolicLinksSync();
  aliases?[absolute] = resolved;
  return resolved;
}

Future<String> _hash(String path) async {
  final result = await captureProcess(
    Platform.isMacOS ? '/usr/bin/shasum' : '/usr/bin/sha256sum',
    Platform.isMacOS ? ['-a', '256', path] : [path],
    timeout: const Duration(seconds: 15),
  );
  if (result.exitCode != 0 ||
      result.timedOut ||
      result.outputLimited ||
      result.startError != null ||
      result.captureError != null) {
    throw StateError('Cannot hash $path: ${result.stderr}');
  }
  var digest = result.stdout.split(' ').first.trim();
  // shasum/sha256sum prefix escaped filenames with one backslash.
  if (digest.startsWith(r'\')) digest = digest.substring(1);
  if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(digest)) {
    throw StateError('Invalid SHA-256 output for $path.');
  }
  return digest.toLowerCase();
}

bool _equal(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}

String _relative(String path) {
  final uri = Uri.parse(path);
  if (path.isEmpty ||
      uri.hasScheme ||
      path.startsWith('/') ||
      path.contains('\\') ||
      path.split('/').any((part) => part == '..' || part.isEmpty)) {
    throw ArgumentError(
      'Input/output paths must be relative files without ..: $path',
    );
  }
  return path;
}

// SDK depfiles use Make-style escaping, including escaped spaces/newlines.
List<String> _depfile(String text) {
  var separator = -1;
  for (var i = 0; i < text.length; i++) {
    if (text[i] == '\\') {
      i++;
      continue;
    }
    if (text[i] == ':') {
      separator = i;
      break;
    }
  }
  if (separator < 0) throw StateError('SDK depfile has no target separator.');
  final paths = <String>[];
  var token = StringBuffer();
  void finish() {
    if (token.isNotEmpty) paths.add(token.toString());
    token = StringBuffer();
  }

  for (var i = separator + 1; i < text.length; i++) {
    var character = text[i];
    if (character == '\\') {
      if (++i == text.length)
        throw StateError('Incomplete SDK depfile escape.');
      character = text[i];
      if (character == '\n') continue;
      if (character == '\r' && i + 1 < text.length && text[i + 1] == '\n') {
        i++;
        continue;
      }
      token.write(character);
    } else if (character.trim().isEmpty) {
      finish();
    } else {
      token.write(character);
    }
  }
  finish();
  if (paths.isEmpty) throw StateError('SDK depfile contains no dependencies.');
  return paths;
}

String _sourcePath(String uri, PackageConfig? packages) {
  if (uri.startsWith('package:')) {
    if (packages == null)
      throw StateError('No package configuration for $uri.');
    return resolvePackageUri(packages, sourcePackageUri(uri));
  }
  if (uri.startsWith('file:')) return Uri.parse(uri).toFilePath();
  throw StateError('Cannot pin dependency $uri.');
}

// Only the tool's known closed import graph is walked here. Program inputs use
// the SDK depfile/native resolver's selected closures, not unselected branches.
Set<String> _localClosure(
  Iterable<String> roots,
  PackageConfig? packages,
  String sdkRoot,
  Map<String, String> aliases,
) {
  final files = <String>{};
  final visited = <String>{};
  final pending = roots.toList();
  while (pending.isNotEmpty) {
    final uri = sourceReferenceUri('file:///', pending.removeLast());
    if (!visited.add(uri)) continue;
    final path = _file(_sourcePath(uri, packages), aliases);
    if (path.startsWith('$sdkRoot/') || !path.endsWith('.dart')) continue;
    files.add(path);
    final tokens = scanTokens(
      Scanner(File(path).readAsStringSync(), <Token>[], 0),
    );
    final parser = Parser(tokens, 0, 0, <String>[path]);
    while (parser.tokens[parser.position].kind != tokenEnd) {
      parserMetadata(parser);
      final start = parser.position;
      var kind = 0;
      if (parserIs(parser, 'import')) kind = astImportDirective;
      if (parserIs(parser, 'export')) kind = astExportDirective;
      if (parserIs(parser, 'library')) kind = astLibraryDirective;
      if (parserPartDirective(parser)) kind = astPartDirective;
      if (kind == 0) break;
      parser.position++;
      if (kind == astPartDirective && parserTake(parser, 'of')) {
        kind = parser.tokens[parser.position].kind == tokenIdentifier
            ? astPartOfNameDirective
            : astPartOfUriDirective;
      }
      final directive = parserDirective(parser, kind, start);
      if (kind == astLibraryDirective ||
          kind == astPartOfNameDirective ||
          kind == astPartOfUriDirective)
        continue;
      for (final reference in [
        directive.uri,
        for (final alternative in directive.conditions) alternative.uri,
      ]) {
        if (reference.startsWith('dart:')) continue;
        pending.add(sourceReferenceUri(uri, reference));
      }
    }
  }
  return files;
}

Future<void> programBenchmark(List<String> args, String root) async {
  Directory? work;
  try {
    if (!Platform.isMacOS && !Platform.isLinux)
      throw UnsupportedError('Benchmark platform.');
    final aliases = <String, String>{};
    var entry = '';
    var seed = '$root/build/dartc-seed';
    String? explicitPackages;
    final inputNames = <String>[];
    final outputNames = <String>[];
    var arguments = <String>[];
    for (var i = 0; i < args.length; i++) {
      final option = args[i];
      if (option == '--') {
        arguments = args.sublist(i + 1);
        break;
      }
      if (![
            '--program',
            '--seed',
            '--packages',
            '--input',
            '--check-output',
          ].contains(option) ||
          ++i == args.length) {
        throw ArgumentError(
          'Expected --program <entry> [--seed <native>] [--packages <config>] [--input <relative-file>]... [--check-output <relative-file>]... -- [args...]',
        );
      }
      final value = args[i];
      if (option == '--program') {
        if (entry.isNotEmpty) throw ArgumentError('Duplicate --program.');
        entry = File(value).absolute.path;
        _file(entry, aliases);
      } else if (option == '--seed') {
        seed = value;
      } else if (option == '--packages') {
        explicitPackages = File(value).absolute.path;
        _file(explicitPackages, aliases);
      } else if (option == '--input') {
        inputNames.add(_relative(value));
      } else {
        outputNames.add(_relative(value));
      }
    }
    if (entry.isEmpty) throw ArgumentError('Missing --program <entry>.');
    if (inputNames.toSet().length != inputNames.length ||
        outputNames.toSet().length != outputNames.length) {
      throw ArgumentError('Duplicate input/output path.');
    }
    seed = _file(seed, aliases);
    final sdk = _file(Platform.resolvedExecutable);
    final sdkRoot = File(sdk).parent.parent.resolveSymbolicLinksSync();
    final standard = _file('$root/lib/src/runtime.dart', aliases);
    final sampler = _file('$root/tool/src/measure.dart');
    final cwd = Directory.current.resolveSymbolicLinksSync();
    final build = Directory('$root/build')..createSync(recursive: true);
    final report = File(
      '${build.resolveSymbolicLinksSync()}/program-benchmark.json',
    );
    work = build.createTempSync('program-benchmark-');
    work = Directory(work.resolveSymbolicLinksSync());
    stdout.writeln('Program benchmark work: ${work.path}');
    final packageConfig = compilerPackages(
      File(entry).uri.toString(),
      cwd,
      explicitPackages,
    );
    final emptyConfig = File('${work.path}/empty-package-config.json');
    if (packageConfig == null)
      emptyConfig.writeAsStringSync('{"configVersion":2,"packages":[]}\n');
    final packages = packageConfig?.path ?? emptyConfig.path;
    _file(packages, aliases);
    final nativeSources = collectSources(
      File(entry).uri.toString(),
      File(standard).uri.toString(),
      packageConfig,
      Platform.isLinux ? 1 : 0,
    );
    final data = <String, String>{
      for (final name in inputNames) name: _file('$cwd/$name', aliases),
    };
    final implementation = _localClosure(
      [
        for (final path in [
          '$root/tool/benchmark.dart',
          '$root/tool/src/program_benchmark.dart',
          sampler,
          '$root/tool/src/process.dart',
        ])
          File(path).absolute.uri.toString(),
      ],
      null,
      sdkRoot,
      aliases,
    );
    final sdkInputs = <String>{sdk};
    for (final relative in [
      'version',
      'revision',
      'bin/utils/gen_snapshot',
      'bin/dartaotruntime',
      'bin/dartvm',
      'lib/libraries.json',
      'lib/_internal/vm_platform.dill',
      'lib/_internal/vm_platform_strong.dill',
      'lib/_internal/vm_platform_product.dill',
      'bin/snapshots/dartdev_aot.dart.snapshot',
      'bin/snapshots/gen_kernel_aot.dart.snapshot',
    ]) {
      final file = File('$sdkRoot/$relative');
      if (file.existsSync()) sdkInputs.add(_file(file.path, aliases));
    }
    final pins = <String, String>{};
    Future<void> pin(Iterable<String> paths) async {
      for (final path in paths) {
        if (pins.containsKey(path)) continue;
        if (path == report.path ||
            report.existsSync() &&
                FileSystemEntity.identicalSync(path, report.path)) {
          throw StateError('A benchmark input aliases its report: $path');
        }
        pins[path] = await _hash(path);
      }
    }

    await pin([
      seed,
      packages,
      standard,
      ...data.values,
      ...sdkInputs,
      ...implementation,
    ]);
    // Discover the SDK-selected dependency closure before accepting any samples.
    final discovery = await captureProcess(
      sdk,
      [
        'compile',
        'exe',
        entry,
        '--packages',
        packages,
        '--depfile',
        '${work.path}/sdk.d',
        '-o',
        '${work.path}/discovery',
      ],
      workingDirectory: cwd,
      environment: const {'LC_ALL': 'C', 'PATH': '/usr/bin:/bin', 'CI': 'true'},
      includeParentEnvironment: false,
      timeout: const Duration(seconds: 45),
    );
    File('${work.path}/discovery.json')
        .writeAsStringSync(jsonEncode(discovery.toJson()));
    if (discovery.exitCode != 0 ||
        discovery.timedOut ||
        discovery.outputLimited ||
        discovery.startError != null ||
        discovery.captureError != null) {
      throw StateError('SDK dependency discovery failed: ${discovery.stderr}');
    }
    final sdkPaths = _depfile(File('${work.path}/sdk.d').readAsStringSync())
        .map((path) => File(path).isAbsolute ? path : '$cwd/$path')
        .toList();
    final sdkDependencies = sdkPaths
        .map(
          (path) => _file(File(path).isAbsolute ? path : '$cwd/$path', aliases),
        )
        .toSet();
    final nativeUris = nativeSources.files.map((file) => file.uri).toSet();
    final nativeDependencies = {
      for (final uri in nativeUris)
        _file(_sourcePath(uri, packageConfig), aliases),
    };
    final selectedLocalSources = {
      for (final path in {...sdkDependencies, ...nativeDependencies})
        if (path.endsWith('.dart') && !path.startsWith('$sdkRoot/')) path,
    };
    await pin({...sdkDependencies, ...nativeDependencies});
    // Snapshots preserve evidence; actual compiler reads remain at original paths.
    final snapshots = Directory('${work.path}/inputs')..createSync();
    final snapshotPaths = <String, String>{};
    for (final path in {...selectedLocalSources, packages, ...data.values}) {
      final snapshot = '${snapshots.path}/${snapshotPaths.length}.source';
      File(path).copySync(snapshot);
      snapshotPaths[path] = snapshot;
    }
    final inputCopies = <String, String>{
      for (final name in inputNames) name: snapshotPaths[data[name]]!,
    };
    final manifest = {
      'entry': entry,
      'runtime': standard,
      'packages': packages,
      'arguments': arguments,
      'input_files': data,
      'checked_outputs': outputNames,
      'native_dependencies': nativeDependencies.toList()..sort(),
      'sdk_dependencies': sdkDependencies.toList()..sort(),
      'native_source_uris': nativeUris.toList()..sort(),
      'selected_local_sources': selectedLocalSources.toList()..sort(),
      'sdk_inputs': sdkInputs.toList()..sort(),
      'implementation_inputs': implementation.toList()..sort(),
      'sha256_before': pins,
      'dependency_aliases': aliases,
      'snapshots': snapshotPaths,
      'source_scope': 'Original paths, hash guarded before/after; snapshots are evidence, not an immutable compilation sandbox.',
    };
    File('${work.path}/inputs.json').writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
    );
    File('${work.path}/discovery').deleteSync();
    var sampleIndex = 0;
    Future<Map<String, dynamic>> measure(
      String executable,
      List<String> taskArgs,
      String taskCwd,
    ) async {
      final samplePath = '${work!.path}/sample-${sampleIndex++}.json';
      final driver = await captureProcess(
        sdk,
        [sampler, '--report', samplePath, '--', executable, ...taskArgs],
        workingDirectory: taskCwd,
        environment: const {
          'LC_ALL': 'C',
          'PATH': '/usr/bin:/bin',
          'CI': 'true',
        },
        includeParentEnvironment: false,
        timeout: const Duration(seconds: 45),
      );
      if (driver.exitCode != 0 ||
          driver.timedOut ||
          driver.outputLimited ||
          driver.startError != null ||
          driver.captureError != null ||
          !File(samplePath).existsSync()) {
        File('${work!.path}/driver-failure-$sampleIndex.json')
            .writeAsStringSync(jsonEncode(driver.toJson()));
        throw StateError('Measurement driver failed; work: ${work.path}');
      }
      final raw = jsonDecode(
        File(samplePath).readAsStringSync(),
      ) as Map<String, dynamic>;
      final outcome = raw['outcome'] as Map<String, dynamic>;
      if (outcome['timedOut'] != false ||
          outcome['outputLimited'] != false ||
          outcome['startError'] != null ||
          outcome['captureError'] != null) {
        throw StateError('Task did not complete; raw sample: $samplePath');
      }
      final resource = raw['measurement'] as Map<String, dynamic>?;
      return {
        'sample_report': samplePath,
        'outcome': outcome,
        'measurement_issues': raw['issues'],
        'isolated': true,
        'wall_ms': resource == null
            ? null
            : (resource['wallMicroseconds'] as num) / 1000,
        'user_ms': resource == null
            ? null
            : (resource['userMicroseconds'] as num) / 1000,
        'system_ms': resource == null
            ? null
            : (resource['systemMicroseconds'] as num) / 1000,
        'cpu_ms': resource == null
            ? null
            : ((resource['userMicroseconds'] as num) +
                      (resource['systemMicroseconds'] as num)) /
                  1000,
        'rss_bytes': resource?['kernelPeakRssBytes'],
      };
    }

    final rounds = <Map<String, Object?>>[];
    const names = ['official', 'native'];
    for (var iteration = 0; iteration <= 4; iteration++) {
      final order = iteration.isEven ? names : names.reversed.toList();
      final round = Directory('${work.path}/round-$iteration')..createSync();
      final artifacts = <String, String>{};
      final compilation = <String, Map<String, dynamic>>{};
      for (final name in order) {
        final path = '${round.path}/$name-app';
        final sample = await measure(
          name == 'official' ? sdk : seed,
          name == 'official'
              ? ['compile', 'exe', entry, '--packages', packages, '-o', path]
              : [entry, '--packages', packages, '--std', standard, '-o', path],
          cwd,
        );
        if ((sample['outcome'] as Map)['exitCode'] != 0 ||
            !File(path).existsSync()) {
          throw StateError(
            '$name compilation failed; raw sample: ${sample['sample_report']}',
          );
        }
        sample['image_bytes'] = File(path).lengthSync();
        sample['artifact_sha256'] = await _hash(path);
        artifacts[name] = path;
        compilation[name] = sample;
      }
      final execution = <String, Map<String, dynamic>>{};
      final fileResults = <String, Map<String, Object?>>{};
      final outputBytes = <String, List<int>>{};
      Map<String, dynamic>? expected;
      final runCwd = Directory('${round.path}/task');
      for (final name in order) {
        if (runCwd.existsSync()) runCwd.deleteSync(recursive: true);
        runCwd.createSync();
        for (final input in inputCopies.entries) {
          final destination = File('${runCwd.path}/${input.key}');
          destination.parent.createSync(recursive: true);
          File(input.value).copySync(destination.path);
        }
        final sample = await measure(artifacts[name]!, arguments, runCwd.path);
        execution[name] = sample;
        final outcome = sample['outcome'] as Map<String, dynamic>;
        sample['artifact_sha256_after'] = await _hash(artifacts[name]!);
        if (sample['artifact_sha256_after'] !=
            compilation[name]!['artifact_sha256']) {
          throw StateError(
            '$name artifact changed during execution; raw sample: ${sample['sample_report']}',
          );
        }
        if (outcome['exitCode'] != 0) {
          throw StateError(
            '$name program exited unsuccessfully; raw sample: ${sample['sample_report']}',
          );
        }
        if (expected == null) {
          expected = outcome;
        } else if (expected['exitCode'] != outcome['exitCode'] ||
            expected['stdoutBase64'] != outcome['stdoutBase64'] ||
            expected['stderrBase64'] != outcome['stderrBase64']) {
          throw StateError(
            'Program behavior differs in round $iteration; work: ${round.path}',
          );
        }
        final files = <String, Object?>{};
        for (final output in outputNames) {
          final file = File('${runCwd.path}/$output');
          if (!file.existsSync())
            throw StateError('$name did not produce $output.');
          final resolved = file.resolveSymbolicLinksSync();
          if (!resolved.startsWith('${runCwd.path}/'))
            throw StateError('Output escapes owned task directory: $output');
          final bytes = file.readAsBytesSync();
          if (outputBytes.containsKey(output) &&
              !_equal(outputBytes[output]!, bytes)) {
            throw StateError(
              'Output file $output differs in round $iteration.',
            );
          }
          outputBytes[output] = bytes;
          final saved = File('${round.path}/$name-outputs/$output');
          saved.parent.createSync(recursive: true);
          file.copySync(saved.path);
          files[output] = {
            'snapshot': saved.path,
            'size_bytes': bytes.length,
            'sha256': await _hash(resolved),
          };
        }
        fileResults[name] = files;
      }
      rounds.add({
        'iteration': iteration,
        'warmup': iteration == 0,
        'order': order,
        'compile': compilation,
        'run': execution,
        'output_files': fileResults,
        'behavior_identical': true,
      });
      File('${round.path}/validation.json')
          .writeAsStringSync(jsonEncode(rounds.last));
      // Each accepted compile artifact has now been executed and checked.
      for (final path in artifacts.values) {
        File(path).deleteSync();
      }
    }
    for (final alias in aliases.entries) {
      if (_file(alias.key) != alias.value) {
        throw StateError('Dependency symlink changed: ${alias.key}');
      }
    }
    final after = <String, String>{};
    for (final path in pins.keys) {
      after[path] = await _hash(path);
      if (after[path] != pins[path])
        throw StateError('Benchmark input changed: $path');
    }
    for (final item in snapshotPaths.entries) {
      if (await _hash(item.value) != pins[item.key])
        throw StateError('Input snapshot changed: ${item.value}');
    }
    final medians = <String, Object?>{};
    for (final name in names) {
      final phases = <String, Object?>{};
      for (final phase in ['compile', 'run']) {
        final values = <String, Object?>{};
        for (final metric in [
          'wall_ms',
          'user_ms',
          'system_ms',
          'cpu_ms',
          'rss_bytes',
          if (phase == 'compile') 'image_bytes',
        ]) {
          final samples = <num>[];
          for (final round in rounds.skip(1)) {
            final value = ((round[phase] as Map)[name] as Map)[metric];
            if (value != null) samples.add(value as num);
          }
          samples.sort();
          values[metric] = samples.length == 4
              ? (samples[1] + samples[2]) / 2
              : null;
        }
        phases[phase] = values;
      }
      medians[name] = phases;
    }
    final result = {
      'mode': 'program_official_reference',
      'platform': Platform.operatingSystem,
      'sdk': {'path': sdk, 'version': Platform.version, 'sha256': pins[sdk]},
      'native_compiler': {
        'path': seed,
        'sha256': pins[seed],
        'image_bytes': File(seed).lengthSync(),
      },
      'task': manifest,
      'sha256_after': after,
      'dependency_discovery': {
        'method':
            'One unmeasured SDK compile --depfile before the paired rounds.',
        'outcome': '${work.path}/discovery.json',
      },
      'warmups': 1,
      'samples_per_phase_per_compiler': 4,
      'measurement_run_directory': work.path,
      'same_program_behavior': true,
      'compilation_image_bytes_need_not_match': true,
      'scope': {
        'wall': 'Task spawn through exit/pipes; excludes fresh Dart measurement-driver startup, FFI, hashes and JSON.',
        'run': 'First launch of each newly compiled artifact, including OS loading/signature validation and process startup; file caches are not cleared. This is not sustained execution throughput.',
        'cpu': 'Waited child CPU, including waited descendants if present.',
        'rss': 'Kernel maximum child high-water, not concurrent process-tree total. Darwin bytes; Linux KiB converted to bytes.',
        'unavailable': 'Null with per-sample issues; no time fallback or dropping unavailable samples.',
        'io': 'Lanes reuse the same owned cwd, cleared and repopulated from declared inputs; undeclared external I/O is not frozen.',
      },
      'units': {
        'wall_ms': 'ms',
        'user_ms': 'ms',
        'system_ms': 'ms',
        'cpu_ms': 'ms',
        'rss_bytes': 'bytes',
        'image_bytes': 'bytes',
      },
      'rounds': rounds,
      'medians': medians,
    };
    final accepted = File('${work.path}/accepted.json');
    accepted.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(result)}\n',
    );
    accepted.renameSync(report.path);
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(medians));
    stdout.writeln('Identical program behavior; results: ${report.path}');
  } catch (error) {
    stderr.writeln(error);
    if (work != null) stderr.writeln('Measurement work retained: ${work.path}');
    exitCode = error is ArgumentError ? 64 : 1;
  }
}
