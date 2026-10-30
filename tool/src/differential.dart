import 'dart:convert';
import 'dart:io';

import 'process.dart';

const _json = JsonEncoder.withIndent('  ');

void writeJson(File file, Object value) {
  file.writeAsStringSync('${_json.convert(value)}\n');
}

Future<String> fileHash(String path) async {
  final result = await captureProcess(
    Platform.isMacOS ? '/usr/bin/shasum' : '/usr/bin/sha256sum',
    [
      if (Platform.isMacOS) ...['-a', '256'],
      path,
    ],
  );
  if (!processFinished(result) || result.exitCode != 0) {
    throw StateError('Cannot hash $path: ${result.toJson()}');
  }
  return result.stdout.split(RegExp(r'\s+')).first;
}

bool processFinished(ProcessOutcome result) =>
    !result.timedOut &&
    !result.outputLimited &&
    result.startError == null &&
    result.captureError == null &&
    result.exitCode != null;

void copyFiles(Directory from, Directory to, {bool dartOnly = false}) {
  to.createSync(recursive: true);
  for (final item in from.listSync(recursive: true, followLinks: false)) {
    if (item is Link) {
      throw ArgumentError(
        'Case and toolchain snapshots cannot contain links: ${item.path}',
      );
    }
    if (item is! File || dartOnly && !item.path.endsWith('.dart')) continue;
    final prefix = from.path.endsWith('/') ? from.path : '${from.path}/';
    final relative = item.path.substring(prefix.length);
    final destination = File('${to.path}/$relative');
    destination.parent.createSync(recursive: true);
    item.copySync(destination.path);
  }
}

class DifferentialSession {
  final Directory directory;
  final Map<String, Object?> metadata;

  DifferentialSession(this.directory, this.metadata);

  String get sdk => metadata['sdk'] as String;
  String get compiler => '${directory.path}/compiler/bin/dartc.dart';
  String get native => '${directory.path}/engine';
  String get runtime => '${directory.path}/runtime/${metadata['runtimeFile']}';
  Duration get timeout => Duration(milliseconds: metadata['timeoutMs'] as int);

  static Future<DifferentialSession> create(
    String root,
    String engine,
    String standard, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final output = Directory('$root/build/fuzz')..createSync(recursive: true);
    final folder = output.createTempSync('run-');
    try {
      for (final name in ['bin', 'lib']) {
        copyFiles(
          Directory('$root/$name'),
          Directory('${folder.path}/compiler/$name'),
          dartOnly: true,
        );
      }
      copyFiles(
        Directory('$root/tool'),
        Directory('${folder.path}/runner'),
        dartOnly: true,
      );
      final source = File(standard).absolute;
      copyFiles(
        source.parent,
        Directory('${folder.path}/runtime'),
        dartOnly: true,
      );
      File('${folder.path}/collect-inputs.dart').writeAsStringSync(r'''
import 'dart:convert';
import 'dart:io';
import 'compiler/lib/src/driver/packages.dart';
import 'compiler/lib/src/source.dart';

void main(List<String> args) {
  final program = collectSources(
    args[0],
    args[1],
    compilerPackages(args[0], Directory.current.path, args[2]),
    Platform.isLinux ? 1 : 0,
  );
  print(jsonEncode([for (final file in program.files) file.input.path]));
}
''');
      File(engine).copySync('${folder.path}/engine');
      writeJson(File('${folder.path}/packages.json'), {
        'configVersion': 2,
        'packages': [],
      });
      final chmod = await captureProcess('/bin/chmod', [
        '755',
        '${folder.path}/engine',
      ]);
      if (!processFinished(chmod) || chmod.exitCode != 0)
        throw StateError('Cannot copy native engine.');
      final metadata = <String, Object?>{
        'schema': 2,
        'sdk': Platform.resolvedExecutable,
        'sdkVersion': Platform.version,
        'platform': Platform.operatingSystem,
        'osVersion': Platform.operatingSystemVersion,
        'runtimeFile': source.uri.pathSegments.last,
        'timeoutMs': timeout.inMilliseconds,
        'originalCompiler': File(engine).absolute.path,
        'originalRuntime': source.path,
        'identities': <String, String>{},
        'sdkFiles': [
          for (final relative in [
            'bin/dartvm',
            'bin/dartaotruntime',
            'bin/snapshots/dartdev_aot.dart.snapshot',
            'bin/snapshots/gen_kernel_aot.dart.snapshot',
            'bin/snapshots/kernel-service.dart.snapshot',
            'lib/_internal/vm_platform_strong.dill',
            'lib/_internal/vm_platform_strong_product.dill',
            'lib/libraries.json',
            'version',
            'revision',
          ])
            if (File(
              '${File(Platform.resolvedExecutable).parent.parent.path}/$relative',
            ).existsSync())
              relative,
        ],
      };
      final session = DifferentialSession(folder, metadata);
      metadata['identities'] = await session.identities();
      writeJson(File('${folder.path}/session.json'), metadata);
      return session;
    } catch (_) {
      folder.deleteSync(recursive: true);
      rethrow;
    }
  }

  static Future<DifferentialSession> open(Directory directory) async {
    final data = (jsonDecode(
      File('${directory.path}/session.json').readAsStringSync(),
    ) as Map).cast<String, Object?>();
    if (data['schema'] != 2 ||
        data['sdkVersion'] != Platform.version ||
        data['platform'] != Platform.operatingSystem) {
      throw StateError(
        'Replay requires the recorded SDK version and platform.',
      );
    }
    final session = DifferentialSession(directory, data);
    if (jsonEncode(await session.identities()) !=
        jsonEncode(data['identities'])) {
      throw StateError(
        'Recorded toolchain changed; refusing an unpinned replay.',
      );
    }
    return session;
  }

  Future<Map<String, String>> identities() async {
    final files =
        directory
            .listSync(recursive: true)
            .whereType<File>()
            .where(
              (file) =>
                  file.path.endsWith('.dart') &&
                      (file.path.startsWith('${directory.path}/compiler/') ||
                          file.path.startsWith('${directory.path}/runtime/') ||
                          file.path.startsWith('${directory.path}/runner/')) ||
                  file.path == '${directory.path}/collect-inputs.dart' ||
                  file.path == native ||
                  file.path == '${directory.path}/packages.json',
            )
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    final sdkFiles = (metadata['sdkFiles'] as List).cast<String>();
    final sdkRoot = File(sdk).parent.parent.path;
    final paths = [
      sdk,
      for (final path in sdkFiles) '$sdkRoot/$path',
      for (final file in files) file.path,
    ];
    final hashes = await captureProcess(
      Platform.isMacOS ? '/usr/bin/shasum' : '/usr/bin/sha256sum',
      [
        if (Platform.isMacOS) ...['-a', '256'],
        ...paths,
      ],
    );
    final lines = hashes.stdout.trim().split('\n');
    if (!processFinished(hashes) ||
        hashes.exitCode != 0 ||
        lines.length != paths.length ||
        lines.any((line) => !RegExp(r'^[0-9a-f]{64} ').hasMatch(line))) {
      throw StateError(
        'Cannot fingerprint the saved toolchain: ${hashes.toJson()}',
      );
    }
    return {
      'sdkExecutable': lines[0].substring(0, 64),
      for (var i = 0; i < sdkFiles.length; i++)
        'sdk/${sdkFiles[i]}': lines[i + 1].substring(0, 64),
      for (var i = 0; i < files.length; i++)
        files[i].path.substring(directory.path.length + 1):
            lines[i + 1 + sdkFiles.length].substring(0, 64),
    };
  }

  Future<DifferentialResult> evaluate(Directory caseDirectory) async {
    final data = (jsonDecode(
      File('${caseDirectory.path}/case.json').readAsStringSync(),
    ) as Map).cast<String, Object?>();
    final kind = data['kind'];
    if (![
      'supported',
      'unsupported',
      'invalid',
      'runtimeFailure',
    ].contains(kind))
      throw FormatException('Unknown case kind $kind');
    final entry = data['entry'] as String;
    if (Uri.parse(entry).hasScheme ||
        entry.startsWith('/') ||
        entry.split('/').contains('..'))
      throw FormatException('Entry must be inside the saved project.');
    final arguments = (data['arguments'] as List? ?? []).cast<String>();
    final project = Directory('${caseDirectory.path}/project');
    final inputFiles = [
      File('${caseDirectory.path}/case.json'),
      ...project
          .listSync(recursive: true, followLinks: false)
          .whereType<File>(),
    ]..sort((a, b) => a.path.compareTo(b.path));
    final inputHashes = {
      for (final file in inputFiles)
        file.path.substring(caseDirectory.path.length + 1): await fileHash(
          file.path,
        ),
    };
    final localPackages = File(
      '${project.path}/.dart_tool/package_config.json',
    );
    final packages = localPackages.existsSync()
        ? localPackages.path
        : '${directory.path}/packages.json';
    final artifacts = Directory('${caseDirectory.path}/artifacts')
      ..createSync();
    final stages = <String, ProcessOutcome>{};
    Future<ProcessOutcome> execute(
      String name,
      String executable,
      List<String> arguments,
    ) async {
      final result = await captureProcess(
        executable,
        arguments,
        workingDirectory: project.path,
        environment: {'LC_ALL': 'C', 'PATH': '/usr/bin:/bin', 'CI': 'true'},
        includeParentEnvironment: false,
        timeout: timeout,
      );
      stages[name] = result;
      return result;
    }

    for (final lane in ['reference', 'host', 'native']) {
      final output =
          '${artifacts.path}/$lane${lane == 'reference' ? '.dill' : ''}';
      final old = File(output);
      if (old.existsSync()) old.deleteSync();
      final result = lane == 'reference'
          ? await execute('$lane.compile', sdk, [
              'compile',
              'kernel',
              '--packages=$packages',
              '--depfile=${artifacts.path}/reference.d',
              entry,
              '-o',
              output,
            ])
          : await execute('$lane.compile', lane == 'host' ? sdk : native, [
              if (lane == 'host') '--packages=${directory.path}/packages.json',
              if (lane == 'host') compiler,
              entry,
              '--std',
              runtime,
              '--packages',
              packages,
              '-o',
              output,
            ]);
      if (lane == 'reference' &&
          processFinished(result) &&
          result.exitCode == 0) {
        final dependencies = File('${artifacts.path}/reference.d')
            .readAsStringSync();
        // SDK depfiles use backslash escaping for whitespace and punctuation.
        final paths = <String>[];
        var word = StringBuffer();
        final tail = dependencies.substring(dependencies.indexOf(': ') + 2);
        for (var i = 0; i < tail.length; i++) {
          var char = tail[i];
          if (char == r'\' && i + 1 < tail.length) {
            word.write(tail[++i]);
          } else if (char.trim().isEmpty) {
            if (word.isNotEmpty) paths.add(word.toString());
            word = StringBuffer();
          } else {
            word.write(char);
          }
        }
        if (word.isNotEmpty) paths.add(word.toString());
        final sdkRoot = File(sdk).parent.parent.path;
        for (final dependency in paths) {
          final uri = Uri.parse(dependency);
          final path = uri.scheme == 'file'
              ? uri.toFilePath()
              : File(dependency).absolute.path;
          if (!path.startsWith('${project.path}/') &&
              !path.startsWith('$sdkRoot/') &&
              path != packages) {
            final outcome = DifferentialResult(
              kind as String,
              stages,
              'invalid-contract:external-dependency:$path',
              inputHashes: inputHashes,
            );
            writeJson(
              File('${caseDirectory.path}/result.json'),
              outcome.toJson(),
            );
            return outcome;
          }
        }
      }
    }
    if (kind != 'invalid' &&
        ['reference', 'host', 'native'].every(
          (lane) =>
              processFinished(stages['$lane.compile']!) &&
              stages['$lane.compile']!.exitCode == 0,
        )) {
      final collected = await execute('inputs.collect', sdk, [
        '--packages=${directory.path}/packages.json',
        '${directory.path}/collect-inputs.dart',
        File('${project.path}/$entry').uri.toString(),
        File(runtime).uri.toString(),
        packages,
      ]);
      var violation = '';
      if (!processFinished(collected) || collected.exitCode != 0) {
        violation = 'invalid-contract:native-dependency-discovery';
      } else {
        final roots = [
          project,
          Directory('${directory.path}/runtime'),
          Directory('${directory.path}/compiler'),
        ].map((folder) => '${folder.resolveSymbolicLinksSync()}/').toList();
        for (final path
            in (jsonDecode(collected.stdout) as List).cast<String>()) {
          final actual = File(path).resolveSymbolicLinksSync();
          if (!roots.any(actual.startsWith)) {
            violation = 'invalid-contract:external-dependency:$actual';
            break;
          }
        }
      }
      if (violation != '') {
        final outcome = DifferentialResult(
          kind as String,
          stages,
          violation,
          inputHashes: inputHashes,
        );
        writeJson(File('${caseDirectory.path}/result.json'), outcome.toJson());
        return outcome;
      }
    }
    for (final lane in ['reference', 'host', 'native']) {
      final compiled = stages['$lane.compile']!;
      if (kind != 'invalid' &&
          processFinished(compiled) &&
          compiled.exitCode == 0) {
        final output =
            '${artifacts.path}/$lane${lane == 'reference' ? '.dill' : ''}';
        await execute('$lane.run', lane == 'reference' ? sdk : output, [
          if (lane == 'reference') output,
          ...arguments,
        ]);
      }
    }
    final result = DifferentialResult(
      kind as String,
      stages,
      _classify(data, stages),
      generated: data['model'] != null,
      inputHashes: inputHashes,
    );
    writeJson(File('${caseDirectory.path}/result.json'), result.toJson());
    return result;
  }
}

String _classify(
  Map<String, Object?> contract,
  Map<String, ProcessOutcome> stages,
) {
  for (final entry in stages.entries) {
    final value = entry.value;
    if (value.startError != null || value.captureError != null)
      return 'capture:${entry.key}';
    if (value.timedOut) return 'timeout:${entry.key}';
    if (value.outputLimited) return 'output-limit:${entry.key}';
    if (value.exitCode! < 0) return 'crash:${entry.key}:${value.exitCode}';
  }
  final reference = stages['reference.compile']!;
  final host = stages['host.compile']!;
  final native = stages['native.compile']!;
  final kind = contract['kind'];
  if (kind == 'invalid') {
    if (reference.exitCode != 254 ||
        contract['referenceError'] is! String ||
        (contract['referenceError'] as String).isEmpty ||
        !reference.stderr.contains(contract['referenceError'] as String))
      return 'invalid-contract:reference-did-not-reject';
    if (!_sourceRejection(host, contract) ||
        !_sourceRejection(native, contract))
      return 'invalid-accepted-or-abnormal-exit';
    return 'pass';
  }
  if (reference.exitCode != 0) return 'invalid-contract:reference-compile';
  if (kind != 'runtimeFailure' && stages['reference.run']!.exitCode != 0)
    return 'invalid-contract:reference-runtime';
  if (host.exitCode != native.exitCode) return 'host-divergence:compile';
  if (host.exitCode != 0) {
    if (base64Encode(host.stdoutBytes) != base64Encode(native.stdoutBytes) ||
        base64Encode(host.stderrBytes) != base64Encode(native.stderrBytes))
      return 'host-divergence:compile-diagnostic';
    if (kind == 'unsupported' &&
        _sourceRejection(host, contract) &&
        _sourceRejection(native, contract))
      return 'capability-gap';
    return 'compile-rejected:${host.exitCode}';
  }
  final expected = stages['reference.run']!;
  final hosted = stages['host.run']!;
  final actual = stages['native.run']!;
  bool equal(ProcessOutcome a, ProcessOutcome b) =>
      a.exitCode == b.exitCode &&
      base64Encode(a.stdoutBytes) == base64Encode(b.stdoutBytes) &&
      base64Encode(a.stderrBytes) == base64Encode(b.stderrBytes);
  if (!equal(hosted, actual)) return 'host-divergence:run';
  if (kind == 'runtimeFailure') {
    final failure = (contract['failure'] as Map).cast<String, Object?>();
    if (expected.exitCode == 0 ||
        failure['referenceError'] is! String ||
        (failure['referenceError'] as String).isEmpty ||
        !expected.stderr.contains(failure['referenceError'] as String))
      return 'invalid-contract:reference-runtime';
    if (actual.exitCode != (failure['nativeExit'] ?? 70) ||
        !(failure['nativeError'] == ''
            ? actual.stderr == ''
            : actual.stderr.contains(failure['nativeError'] as String)) ||
        base64Encode(actual.stdoutBytes) != base64Encode(expected.stdoutBytes))
      return 'runtime-contract-difference';
    return 'pass';
  }
  if (expected.exitCode != 0) return 'invalid-contract:reference-runtime';
  return equal(expected, actual) ? 'pass' : 'reference-divergence:run';
}

String _compileStdout(ProcessOutcome result) {
  final index = result.arguments.indexOf('-o');
  var text = result.stdout;
  if (index >= 0 && index + 1 < result.arguments.length) {
    final output = result.arguments[index + 1];
    text = text.replaceAll(
      RegExp('^${RegExp.escape(output)}: [0-9]+ bytes', multiLine: true),
      '<output>: <size> bytes',
    );
    text = text.replaceAll(output, '<output>');
  }
  return text;
}

bool _sourceRejection(ProcessOutcome result, Map<String, Object?> contract) {
  final expected = contract['nativeDiagnostic'];
  if (result.exitCode != 1 ||
      result.stdout.isNotEmpty ||
      expected is! String ||
      expected.isEmpty)
    return false;
  final path = RegExp.escape(result.workingDirectory + '/');
  final diagnostic = RegExp('^$path[^\\n]+:[1-9][0-9]*:[1-9][0-9]*: ([^\\n]*)')
      .firstMatch(result.stderr);
  return diagnostic != null && diagnostic[1]!.contains(expected);
}

class DifferentialResult {
  final String kind;
  final Map<String, ProcessOutcome> stages;
  final String verdict;
  final bool generated;
  final Map<String, String> inputHashes;
  DifferentialResult(
    this.kind,
    this.stages,
    this.verdict, {
    this.generated = false,
    this.inputHashes = const {},
  });
  bool get failed => verdict != 'pass' && verdict != 'capability-gap';

  Map<String, Object?>? get witness {
    if (generated &&
        (verdict.startsWith('host-divergence:compile') ||
            verdict.startsWith('compile-rejected:'))) {
      for (final phase in ['host.compile', 'native.compile']) {
        final outcome = stages[phase]!;
        final text = outcome.stderr;
        if (outcome.exitCode != 255 ||
            !text.startsWith('Unhandled exception:\n'))
          continue;
        final frames = text.split('\n');
        final owner = frames
            .where(
              (line) => line.startsWith('#') && line.contains('/compiler/'),
            )
            .firstOrNull;
        if (owner == null) continue;
        return {
          'phase': phase,
          'exception': text.split(RegExp(r'\n#0\s')).first.trim(),
          'owner': owner.replaceFirst(RegExp(r'^#\d+\s+'), ''),
        };
      }
    }
    if (!generated ||
        (verdict != 'host-divergence:run' &&
            verdict != 'reference-divergence:run'))
      return null;
    final runs = [
      for (final lane in ['reference', 'host', 'native']) stages['$lane.run']!,
    ];
    if (runs.any((run) => run.exitCode != 0)) return null;
    final lines = [for (final run in runs) run.stdout.split('\n')];
    for (var i = 0; i < lines[0].length; i++) {
      if (lines.any((lane) => i >= lane.length)) return null;
      if (lines[0][i] == lines[1][i] && lines[1][i] == lines[2][i]) continue;
      final labels = [
        for (final lane in lines)
          RegExp(r'^(p[0-9]+|end):').firstMatch(lane[i])?.group(1),
      ];
      if (labels[0] == null || labels.any((label) => label != labels[0]))
        return null;
      return {
        'probe': labels[0],
        'occurrence': lines[0]
            .take(i)
            .where((line) => line.startsWith('${labels[0]}:'))
            .length,
        'reference': lines[0][i],
        'host': lines[1][i],
        'native': lines[2][i],
      };
    }
    return null;
  }

  // A generated result needs the same labelled observation and prior trace.
  // A compiler exception needs the same preamble and compiler-owned frame.
  // Other outcomes retain their complete observations, including source locations.
  String get fingerprint => jsonEncode({
    'kind': kind,
    'verdict': verdict,
    'witness': witness,
    'stages': {
      for (final entry in stages.entries)
        entry.key: {
          'exit': entry.value.exitCode,
          'timeout': entry.value.timedOut,
          'outputLimit': entry.value.outputLimited,
          'startError': entry.value.startError,
          'captureError': entry.value.captureError,
          'stdout': entry.key.endsWith('.compile')
              ? _compileStdout(entry.value)
              : witness != null
              ? '<witness>'
              : base64Encode(entry.value.stdoutBytes),
          'stderr': entry.key.endsWith('.compile')
              ? (witness != null && witness!['phase'] == entry.key
                    ? '<witness>'
                    : entry.value.stderr)
              : base64Encode(entry.value.stderrBytes),
        },
    },
  });

  Map<String, Object?> toJson() => {
    'kind': kind,
    'verdict': verdict,
    'fingerprint': fingerprint,
    'inputHashes': inputHashes,
    'witness': witness,
    'stages': {
      for (final entry in stages.entries) entry.key: entry.value.toJson(),
    },
  };
}
