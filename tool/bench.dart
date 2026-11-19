import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Measures fixed compiler workloads and records bounded process outcomes.
///
/// Reports identify exact inputs and distinguish sampled RSS from a peak.
Future<void> main(List<String> arguments) async {
  final options = _Options.parse(arguments);
  if (options.help) {
    stdout.writeln(_usage);
    return;
  }
  final selected = (options.only == null ? defaultFixtures : fixtures)
      .where(
        (fixture) =>
            options.only == null || options.only!.contains(fixture.name),
      )
      .toList();
  final inputs = {
    for (final fixture in selected)
      fixture.name: await _fixtureIdentity(fixture, execute: options.execute),
  };
  final harness = await _fileIdentity(Platform.script.toFilePath());
  final baseline = _readBaseline(options, inputs);
  final lock = await _benchLock();
  if (lock == null) {
    exitCode = 1;
    return;
  }
  try {
    final source = options.compiler == null
        ? await _sourceIdentity(built: options.build, api: options.api)
        : null;
    var compiler = options.compiler == null
        ? _Compiler(Platform.resolvedExecutable, [
            'run',
            if (options.api) _apiDriver else 'bin/dartc.dart',
          ])
        : _Compiler(_resolveExecutable(options.compiler!), const []);
    _Measurement? build;
    if (options.build) {
      final built = File('build/bench/dartc').absolute.path;
      build = await _measure(Platform.resolvedExecutable, [
        'run',
        'tool/build.dart',
        built,
      ], options.timeout);
      if (build.failed) {
        stderr.writeln(
          '${build.stdout}\n${build.stderr}\n${build.error ?? ''}',
        );
        exitCode = 1;
        return;
      }
      compiler = _Compiler(built, const []);
    }
    final binary = await _fileIdentity(compiler.executable);
    final rows = <_Row>[];
    for (final fixture in selected) {
      rows.add(await _run(fixture, compiler, options, inputs[fixture.name]!));
    }
    final inputChanges = <String>[];
    if ((await _fileIdentity(compiler.executable))['sha256'] !=
        binary['sha256']) {
      inputChanges.add('compiler executable');
    }
    if (source != null &&
        (await _sourceIdentity(
              built: options.build,
              api: options.api,
            ))['sha256'] !=
            source['sha256']) {
      inputChanges.add('compiler sources or SDK resources');
    }
    for (final fixture in selected) {
      final current = await _fixtureIdentity(fixture, execute: options.execute);
      if (jsonEncode(current) != jsonEncode(inputs[fixture.name])) {
        inputChanges.add(fixture.path);
      }
    }
    final document = <String, Object?>{
      'format': 2,
      'harness': harness,
      'created': DateTime.now().toUtc().toIso8601String(),
      'host': _hostIdentity(),
      'compiler': {
        ...binary,
        'prefix': compiler.prefix,
        'mode': options.compilerMode,
        'source': source,
      },
      'target': options.target,
      'configuration': options.toJson(),
      'environmentSha256': _environmentIdentity(),
      'rssSampling': {'scope': 'direct compiler process', 'intervalUs': 100000},
      'timing':
          'wall microseconds from process start through exit and pipe drain',
      'inputChanges': inputChanges,
      if (build != null) 'build': build.toJson(),
      'fixtures': {for (final row in rows) row.name: row.toJson()},
    };
    final output = File(options.output ?? 'build/bench/latest.json');
    await output.parent.create(recursive: true);
    await output.writeAsString(
      const JsonEncoder.withIndent('  ').convert(document),
    );
    _print(rows, baseline, options);
    if (inputChanges.isNotEmpty) {
      stderr.writeln(
        'Benchmark inputs changed during measurement: ${inputChanges.join(', ')}',
      );
    }
    if (inputChanges.isNotEmpty ||
        rows.any(
          (row) =>
              row.failed ||
              baseline != null && row.regressed(baseline, options),
        )) {
      exitCode = 1;
    }
  } finally {
    if (lock.existsSync()) lock.deleteSync();
  }
}

typedef _Baseline = Map<String, ({int elapsedUs, int bytes, int? runMedianUs})>;

_Baseline? _readBaseline(
  _Options options,
  Map<String, Map<String, Object?>> inputs,
) {
  final path = options.baseline;
  if (path == null) return null;
  final document = jsonDecode(File(path).readAsStringSync());
  if (document is! Map<String, dynamic> ||
      document['format'] != 2 ||
      document['fixtures'] is! Map<String, dynamic> ||
      document['inputChanges'] is! List ||
      (document['inputChanges'] as List).isNotEmpty) {
    throw const FormatException(
      'Invalid benchmark baseline: expected an unchanged format 2 report.',
    );
  }
  final configuration = document['configuration'];
  final compiler = document['compiler'];
  final host = document['host'];
  if (document['target'] != options.target ||
      compiler is! Map ||
      compiler['mode'] != options.compilerMode ||
      host is! Map ||
      _hostIdentity().entries.any((entry) => host[entry.key] != entry.value) ||
      configuration is! Map ||
      configuration['execute'] != options.execute ||
      configuration['runRepeats'] != options.runRepeats) {
    throw const FormatException(
      'Invalid benchmark baseline: host, compiler mode, target or execution configuration differs.',
    );
  }
  final previous = document['fixtures'] as Map<String, dynamic>;
  final baseline = <String, ({int elapsedUs, int bytes, int? runMedianUs})>{};
  for (final fixture in fixtures) {
    if (!inputs.containsKey(fixture.name)) continue;
    final row = previous[fixture.name];
    if (row is! Map<String, dynamic> ||
        row['failed'] != false ||
        row['exitCode'] != 0 ||
        row['timedOut'] != false ||
        row['outputComplete'] != true ||
        row['error'] != null ||
        row['failure'] != null ||
        row['source'] is! Map ||
        (row['source'] as Map)['sha256'] != inputs[fixture.name]!['sha256'] ||
        jsonEncode(row['source']['imports']) !=
            jsonEncode(inputs[fixture.name]!['imports'])) {
      throw FormatException(
        'Invalid benchmark baseline: ${fixture.name} requires an unchanged successful workload.',
      );
    }
    final runs = row['runs'];
    final runCount = options.execute && fixture.run ? options.runRepeats : 0;
    if (runs is! List ||
        runs.length != runCount ||
        runs.any(
          (run) =>
              run is! Map ||
              run['exitCode'] != 0 ||
              run['timedOut'] != false ||
              run['outputComplete'] != true ||
              run['matched'] != true ||
              run['error'] != null,
        )) {
      throw FormatException(
        'Invalid benchmark baseline: ${fixture.name} has incomplete or failed execution records.',
      );
    }
    if (options.execute && fixture.hostTest != null) {
      bool succeeded(Object? process) =>
          process is Map &&
          process['exitCode'] == 0 &&
          process['timedOut'] == false &&
          process['outputComplete'] == true &&
          process['error'] == null;
      if (row['source']['hostExpectationSha256'] !=
              inputs[fixture.name]!['hostExpectationSha256'] ||
          !succeeded(row['hostVerification']) ||
          (fixture.linksHost || fixture.hostProvider != null) &&
              !succeeded(row['hostPreparation'])) {
        throw FormatException(
          'Invalid benchmark baseline: ${fixture.name} requires a successful host test.',
        );
      }
    }
    final elapsedUs = row['elapsedUs'];
    final bytes = row['bytes'];
    final runMedianUs = row['runMedianUs'];
    if (elapsedUs is! int ||
        elapsedUs <= 0 ||
        bytes is! int ||
        bytes <= 0 ||
        (options.execute &&
            fixture.run &&
            (runMedianUs is! int || runMedianUs <= 0))) {
      throw FormatException(
        'Invalid benchmark baseline: ${fixture.name} requires positive comparison measurements.',
      );
    }
    baseline[fixture.name] = (
      elapsedUs: elapsedUs,
      bytes: bytes,
      runMedianUs: options.execute && fixture.run ? runMedianUs as int : null,
    );
  }
  return baseline;
}

const defaultFixtures = <_Fixture>[
  _Fixture(
    'hello',
    'tool/bench/fixtures/hello.dart',
    .executable,
    run: true,
    expected: 'hello\n',
  ),
  _Fixture(
    'print_integers',
    'tool/bench/fixtures/print_integers.dart',
    .executable,
    run: true,
    expected: '42\n43\n',
  ),
  _Fixture(
    'map_sum',
    'tool/bench/fixtures/map_sum.dart',
    .executable,
    run: true,
    expected: '59\n',
  ),
  _Fixture(
    'persistent_cell',
    'tool/bench/fixtures/persistent_cell.dart',
    .executable,
    run: true,
    expected: '499500\n',
  ),
  _Fixture(
    'system_libraries',
    'test/compiler/fixtures/system_libraries.dart',
    .executable,
    run: true,
    expected: 'system_libraries:ok\n',
  ),
];

const _apiDriver = 'tool/bench/compile_api.dart';

const fixtures = <_Fixture>[
  ...defaultFixtures,
  _Fixture(
    'checked_index',
    'test/compiler/fixtures/checked_index.dart',
    .shared,
    hostTest: 'test/compiler/checked_index_test.dart',
  ),
  _Fixture(
    'checked_index_object',
    'test/compiler/fixtures/checked_index.dart',
    .object,
    hostTest: 'tool/bench/fixtures/checked_index_host.c',
  ),
  _Fixture(
    'checked_index_static',
    'test/compiler/fixtures/checked_index.dart',
    .archive,
    hostTest: 'tool/bench/fixtures/checked_index_host.c',
  ),
  _Fixture(
    'control_flow',
    'test/compiler/fixtures/control_flow.dart',
    .shared,
    imports: ['test/optimizer/fixtures/zone_state.dart'],
    hostTest: 'test/compiler/control_flow_test.dart',
    hostTestImports: ['test/compiler/fixtures/control_flow_ffi.dart'],
  ),
  _Fixture(
    'generic_member_carriers',
    'test/compiler/fixtures/generic_member_carriers.dart',
    .shared,
    hostTest: 'test/compiler/generic_member_carriers_test.dart',
  ),
  _Fixture(
    'generic_cell_storage',
    'test/compiler/fixtures/generic_cell_storage.dart',
    .shared,
    hostTest: 'test/compiler/generic_cell_storage_test.dart',
  ),
  _Fixture(
    'same_heap_finalizer',
    'test/compiler/fixtures/same_heap_finalizer.dart',
    .shared,
    hostTest: 'test/compiler/same_heap_finalizer_test.dart',
    hostProvider: (
      fixture: 'native_finalizer_callback',
      source: 'test/compiler/fixtures/native_finalizers_assets.dart',
    ),
  ),
];

final class const _Fixture(
  final String name,
  final String path,
  final _Kind kind, {
  final bool run = false,
  final String? expected,
  final List<String> imports = const [],
  final String? hostTest,
  final List<String> hostTestImports = const [],
  final ({String fixture, String source})? hostProvider,
}) {
  bool get linksHost => kind == .object || kind == .archive;

  String assetRoot(String target) => 'build/bench/${_safe(target)}';

  String output(String target) {
    final directory = assetRoot(target);
    return switch (kind) {
      .executable => '$directory/$name',
      .object => '$directory/compiler/$name.o',
      .archive => '$directory/compiler/$name.a',
      .shared =>
        target.contains('linux')
            ? '$directory/compiler/$name.so'
            : '$directory/compiler/$name.dylib',
    };
  }
}

enum _Kind() {
  executable,
  shared,
  object,
  archive;

  String get outputKind => this == .archive ? 'static' : name;
}

final class _Options(
  final bool help,
  final Set<String>? only,
  final String? compiler,
  final String target,
  final String? output,
  final String? baseline,
  final Duration timeout,
  final Duration runTimeout,
  final bool execute,
  final double maxTimeGrowth,
  final double maxSizeGrowth,
  final bool build,
  final bool api,
  final int runRepeats,
) {
  String get compilerMode => api
      ? 'api'
      : compiler != null
      ? 'external'
      : build
      ? 'built'
      : 'source';

  factory parse(List<String> arguments) {
    var help = false;
    Set<String>? only;
    String? compiler;
    var target = _hostTarget();
    String? output;
    String? baseline;
    var timeout = const Duration(seconds: 120);
    var runTimeout = const Duration(seconds: 120);
    var execute = true;
    var maxTimeGrowth = 10.0;
    var maxSizeGrowth = 5.0;
    var build = false;
    var api = false;
    var runRepeats = 3;
    for (final argument in arguments) {
      if (argument == '--help' || argument == '-h') {
        help = true;
      } else if (argument.startsWith('--only=')) {
        only = argument.substring('--only='.length).split(',').toSet();
      } else if (argument.startsWith('--compiler=')) {
        compiler = argument.substring('--compiler='.length);
      } else if (argument.startsWith('--target=')) {
        target = argument.substring('--target='.length);
      } else if (argument.startsWith('--output=')) {
        output = argument.substring('--output='.length);
      } else if (argument.startsWith('--baseline=')) {
        baseline = argument.substring('--baseline='.length);
      } else if (argument.startsWith('--timeout=')) {
        timeout = Duration(
          seconds: int.parse(argument.substring('--timeout='.length)),
        );
      } else if (argument.startsWith('--run-timeout=')) {
        runTimeout = Duration(
          seconds: int.parse(argument.substring('--run-timeout='.length)),
        );
      } else if (argument == '--compile-only') {
        execute = false;
      } else if (argument.startsWith('--max-time-growth=')) {
        maxTimeGrowth = double.parse(
          argument.substring('--max-time-growth='.length),
        );
      } else if (argument.startsWith('--max-size-growth=')) {
        maxSizeGrowth = double.parse(
          argument.substring('--max-size-growth='.length),
        );
      } else if (argument == '--api') {
        api = true;
      } else if (argument == '--build') {
        build = true;
      } else if (argument.startsWith('--run-repeats=')) {
        runRepeats = int.parse(argument.substring('--run-repeats='.length));
        if (runRepeats < 1) {
          throw ArgumentError.value(
            runRepeats,
            'runRepeats',
            'Must be positive',
          );
        }
      } else {
        throw ArgumentError.value(argument, 'argument', 'Unknown option');
      }
    }
    if (!help) {
      if (api && (build || compiler != null)) {
        throw ArgumentError(
          '--api uses the source Compiler API; choose one compiler mode.',
        );
      }
      const targets = {'macos-arm64', 'macos-x64', 'linux-arm64', 'linux-x64'};
      if (!targets.contains(target) || execute && target != _hostTarget()) {
        throw ArgumentError(
          'Unsupported execution target $target; cross-generation requires --compile-only.',
        );
      }
      if (only != null &&
          (only.isEmpty ||
              only.any(
                (name) => !fixtures.any((fixture) => fixture.name == name),
              ))) {
        throw ArgumentError.value(
          only,
          'only',
          'Unknown or empty fixture selection',
        );
      }
      if (timeout <= Duration.zero ||
          runTimeout <= Duration.zero ||
          !maxTimeGrowth.isFinite ||
          maxTimeGrowth < 0 ||
          !maxSizeGrowth.isFinite ||
          maxSizeGrowth < 0 ||
          build && compiler != null) {
        throw ArgumentError(
          'Timeouts must be positive, growth limits finite and nonnegative, and --build cannot be combined with --compiler.',
        );
      }
    }
    return _Options(
      help,
      only,
      compiler,
      target,
      output,
      baseline,
      timeout,
      runTimeout,
      execute,
      maxTimeGrowth,
      maxSizeGrowth,
      build,
      api,
      runRepeats,
    );
  }

  Map<String, Object?> toJson() => {
    'compileTimeoutUs': timeout.inMicroseconds,
    'runTimeoutUs': runTimeout.inMicroseconds,
    'execute': execute,
    'runRepeats': runRepeats,
    'maxTimeGrowth': maxTimeGrowth,
    'maxSizeGrowth': maxSizeGrowth,
  };
}

final class _Row(
  final _Fixture fixture,
  final Map<String, Object?> source,
  final _Measurement compilation,
  final List<_Measurement> runs,
  final _Measurement? hostVerification,
  final _Measurement? hostPreparation,
  final Map<String, Object?>? artifact,
  final String? failure,
) {
  String get name => fixture.name;
  int get bytes => artifact?['bytes'] as int? ?? 0;
  int? get runMedianUs {
    if (runs.isEmpty) return null;
    final times = [for (final run in runs) run.elapsedUs]..sort();
    return times[times.length ~/ 2];
  }

  bool matches(_Measurement run) =>
      fixture.expected == null ||
      run.stdoutLength == fixture.expected!.length &&
          run.stdout == fixture.expected;
  bool get failed =>
      compilation.failed ||
      (hostVerification?.failed ?? false) ||
      (hostPreparation?.failed ?? false) ||
      failure != null ||
      runs.any((run) => run.failed || !matches(run));

  Map<String, Object?> toJson() => {
    ...compilation.toJson(),
    'source': source,
    'artifact': artifact,
    'bytes': bytes,
    'runMedianUs': runMedianUs,
    if (hostPreparation != null) 'hostPreparation': hostPreparation!.toJson(),
    if (hostVerification != null)
      'hostVerification': hostVerification!.toJson(),
    'runs': [
      for (final run in runs) {...run.toJson(), 'matched': matches(run)},
    ],
    'failure': failure,
    'failed': failed,
  };

  bool regressed(_Baseline baseline, _Options options) {
    final previous = baseline[name]!;
    bool grew(int value, int old, double limit) =>
        (value - old) * 100 / old > limit;
    return grew(
          compilation.elapsedUs,
          previous.elapsedUs,
          options.maxTimeGrowth,
        ) ||
        grew(bytes, previous.bytes, options.maxSizeGrowth) ||
        previous.runMedianUs != null &&
            runMedianUs != null &&
            grew(runMedianUs!, previous.runMedianUs!, options.maxTimeGrowth);
  }
}

Future<_Row> _run(
  _Fixture fixture,
  _Compiler compiler,
  _Options options,
  Map<String, Object?> source,
) async {
  final output = File(fixture.output(options.target));
  await output.parent.create(recursive: true);
  if (FileSystemEntity.typeSync(output.path, followLinks: false) != .notFound) {
    await output.delete();
  }
  final compilation = await _measure(
    compiler.executable,
    [
      ...compiler.prefix,
      fixture.path,
      if (options.api) ...[
        fixture.kind.outputKind,
        options.target,
        output.path,
      ] else ...[
        '--kind',
        fixture.kind == .executable ? 'exe' : fixture.kind.outputKind,
        '--target',
        options.target,
        '-o',
        output.path,
      ],
    ],
    options.timeout,
    sampleRss: true,
  );
  final runs = <_Measurement>[];
  _Measurement? hostVerification;
  _Measurement? hostPreparation;
  Map<String, Object?>? artifact;
  String? failure;
  if (!compilation.failed) {
    if (!output.existsSync()) {
      failure = 'Compiler exited successfully without producing an output.';
    } else {
      artifact = await _fileIdentity(output.path);
      if (options.execute && fixture.run) {
        for (var index = 0; index < options.runRepeats; index++) {
          final run = await _measure(
            output.absolute.path,
            const [],
            options.runTimeout,
          );
          runs.add(run);
          if (run.failed ||
              fixture.expected != null &&
                  (run.stdoutLength != fixture.expected!.length ||
                      run.stdout != fixture.expected)) {
            break;
          }
        }
      }
      if (fixture.hostTest case final String hostTest when options.execute) {
        final environment = {
          'DARTC_TEST_NATIVE_ASSET_ROOT': Directory(
            fixture.assetRoot(options.target),
          ).absolute.path,
        };
        final client = File('${output.path}.host');
        if (fixture.linksHost) {
          if (await client.exists()) await client.delete();
          hostPreparation = await _measure('cc', [
            hostTest,
            output.path,
            '-o',
            client.path,
          ], options.runTimeout);
        } else if (fixture.hostProvider case final provider?) {
          hostPreparation = await _measure(
            Platform.resolvedExecutable,
            [
              'run',
              'tool/build_test_assets.dart',
              options.target,
              '--fixture=${provider.fixture}',
            ],
            options.runTimeout,
            environment: environment,
          );
        }
        if (!(hostPreparation?.failed ?? false)) {
          hostVerification = await _measure(
            fixture.linksHost
                ? client.absolute.path
                : Platform.resolvedExecutable,
            fixture.linksHost
                ? const []
                : ['test', '--reporter=expanded', hostTest],
            options.runTimeout,
            environment: environment,
          );
        }
      }
      if ((runs.isNotEmpty || hostVerification != null) &&
          (await _fileIdentity(output.path))['sha256'] != artifact['sha256']) {
        failure = 'Output changed during execution.';
      }
    }
  }
  return _Row(
    fixture,
    source,
    compilation,
    runs,
    hostVerification,
    hostPreparation,
    artifact,
    failure,
  );
}

final class _Measurement(
  final List<String> command,
  final int? exitCode,
  final int elapsedUs,
  final bool timedOut,
  final bool outputComplete,
  final String stdout,
  final int stdoutLength,
  final String stderr,
  final int stderrLength,
  final String? error,
  final int? sampledMaxRssKiB,
  final int rssSamples,
) {
  bool get failed =>
      exitCode != 0 || timedOut || !outputComplete || error != null;
  Map<String, Object?> toJson() => {
    'command': command,
    'exitCode': exitCode,
    'elapsedUs': elapsedUs,
    'timedOut': timedOut,
    'outputComplete': outputComplete,
    'stdout': stdout,
    'stdoutTruncated': stdout.length != stdoutLength,
    'stderr': stderr,
    'stderrTruncated': stderr.length != stderrLength,
    'error': error,
    'sampledMaxRssKiB': sampledMaxRssKiB,
    'rssSamples': rssSamples,
  };
}

final class _Capture() {
  var tail = '';
  var length = 0;
  void add(String text) {
    length += text.length;
    tail += text;
    if (tail.length > 4000) tail = tail.substring(tail.length - 4000);
  }
}

Future<_Measurement> _measure(
  String executable,
  List<String> arguments,
  Duration timeout, {
  bool sampleRss = false,
  Map<String, String>? environment,
}) async {
  final watch = Stopwatch()..start();
  final out = _Capture();
  final err = _Capture();
  Process process;
  try {
    process = await Process.start(
      executable,
      arguments,
      environment: environment,
    );
  } on ProcessException catch (error) {
    watch.stop();
    return _Measurement(
      [executable, ...arguments],
      null,
      watch.elapsedMicroseconds,
      false,
      false,
      '',
      0,
      '',
      0,
      '$error',
      null,
      0,
    );
  }
  final output = process.stdout
      .transform(const Utf8Decoder(allowMalformed: true))
      .listen(out.add);
  final errors = process.stderr
      .transform(const Utf8Decoder(allowMalformed: true))
      .listen(err.add);
  final drained = [output.asFuture<void>(), errors.asFuture<void>()];
  int? sampledMaxRss;
  var samples = 0;
  Future<void>? sample;
  final sampler = sampleRss
      ? Timer.periodic(const Duration(milliseconds: 100), (_) {
          if (sample != null) return;
          sample = _rssKiB(process.pid)
              .then((rss) {
                if (rss != null) {
                  samples++;
                  if (sampledMaxRss == null || rss > sampledMaxRss!) {
                    sampledMaxRss = rss;
                  }
                }
              })
              .whenComplete(() => sample = null);
        })
      : null;
  int? code;
  var timedOut = false;
  var complete = false;
  String? failure;
  try {
    await Future.wait<void>([
      process.exitCode.then((value) {
        code = value;
      }),
      ...drained,
    ]).timeout(timeout);
    complete = true;
  } on TimeoutException {
    timedOut = true;
    if (code == null) await _terminate(process);
    code = await process.exitCode;
    await Future.wait([output.cancel(), errors.cancel()]);
  } catch (error) {
    failure = '$error';
    if (code == null) await _terminate(process);
    code = await process.exitCode;
    await Future.wait([output.cancel(), errors.cancel()]);
  } finally {
    watch.stop();
    sampler?.cancel();
    await sample;
  }
  return _Measurement(
    [executable, ...arguments],
    code,
    watch.elapsedMicroseconds,
    timedOut,
    complete,
    out.tail,
    out.length,
    err.tail,
    err.length,
    failure,
    sampledMaxRss,
    samples,
  );
}

Future<void> _terminate(Process process) async {
  // Stop new direct children while collecting the currently visible descendants.
  process.kill(ProcessSignal.sigstop);
  try {
    final listing = await Process.run('ps', ['-axo', 'pid=,ppid=']);
    if (listing.exitCode == 0) {
      final parents = <int, int>{};
      for (final line in '${listing.stdout}'.split('\n')) {
        final fields = line.trim().split(RegExp(r'\s+'));
        if (fields.length == 2) {
          final pid = int.tryParse(fields[0]);
          final parent = int.tryParse(fields[1]);
          if (pid != null && parent != null) parents[pid] = parent;
        }
      }
      final descendants = <int>[process.pid];
      for (var index = 0; index < descendants.length; index++) {
        for (final entry in parents.entries) {
          if (entry.value == descendants[index] &&
              !descendants.contains(entry.key)) {
            descendants.add(entry.key);
          }
        }
      }
      for (final child in descendants.reversed) {
        Process.killPid(child, ProcessSignal.sigkill);
      }
    }
  } on ProcessException {
    // The direct child is still killed if process enumeration is unavailable.
  } finally {
    process.kill(ProcessSignal.sigkill);
  }
}

Future<File?> _benchLock() async {
  final result = Process.runSync('git', ['rev-parse', '--git-common-dir']);
  final raw = result.exitCode == 0 ? '${result.stdout}'.trim() : '.git';
  final lock = File('${Directory(raw).absolute.path}/dartc-bench.lock');
  final watch = Stopwatch()..start();
  while (true) {
    if (lock.existsSync()) {
      final owner = int.tryParse(lock.readAsStringSync().trim());
      if (owner != null && !_processAlive(owner)) {
        lock.deleteSync();
      }
    }
    try {
      lock.createSync(exclusive: true);
    } on FileSystemException catch (error) {
      // POSIX EEXIST is contention. Permission, missing-parent and filesystem
      // failures must keep their real cause instead of waiting five minutes.
      if (error.osError?.errorCode != 17) rethrow;
      if (watch.elapsed > const Duration(minutes: 5)) {
        stderr.writeln('Another dartc benchmark holds $lock.');
        return null;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
      continue;
    }
    try {
      lock.writeAsStringSync('$pid\n');
      return lock;
    } on FileSystemException {
      try {
        lock.deleteSync();
      } on FileSystemException {
        // Preserve the original write failure if cleanup also fails.
      }
      rethrow;
    }
  }
}

bool _processAlive(int pid) {
  final result = Process.runSync('kill', ['-0', '$pid']);
  return result.exitCode == 0;
}

Future<int?> _rssKiB(int pid) async {
  try {
    final result = await Process.run('ps', ['-o', 'rss=', '-p', '$pid']);
    if (result.exitCode != 0) return null;
    return int.tryParse('${result.stdout}'.trim());
  } on ProcessException {
    return null;
  }
}

void _print(List<_Row> rows, _Baseline? baseline, _Options options) {
  stdout.writeln(
    'fixture              compile us sampled RSS KiB      bytes       run us status',
  );
  for (final row in rows) {
    final previous = baseline?[row.name];
    final delta = previous != null
        ? ' (${_signed(row.compilation.elapsedUs - previous.elapsedUs)} us)'
        : '';
    final status =
        row.compilation.timedOut ||
            (row.hostVerification?.timedOut ?? false) ||
            (row.hostPreparation?.timedOut ?? false) ||
            row.runs.any((run) => run.timedOut)
        ? 'TIMEOUT'
        : row.failed
        ? 'FAIL'
        : baseline != null && row.regressed(baseline, options)
        ? 'REGRESSION'
        : 'ok';
    final host = row.hostVerification;
    final hostTime = host == null ? '' : ' (host test ${host.elapsedUs} us)';
    stdout.writeln(
      '${row.name.padRight(20)} '
      '${row.compilation.elapsedUs.toString().padLeft(10)} '
      '${(row.compilation.sampledMaxRssKiB?.toString() ?? '-').padLeft(15)} '
      '${row.bytes.toString().padLeft(10)} '
      '${(row.runMedianUs?.toString() ?? '-').padLeft(12)} $status$delta$hostTime',
    );
  }
  if (baseline != null) {
    stdout.writeln(
      'baseline growth limits: compile/run time +${options.maxTimeGrowth}%, size +${options.maxSizeGrowth}%',
    );
  }
}

String _signed(int value) => value >= 0 ? '+$value' : '$value';

String _hostTarget() {
  final os = Platform.isMacOS ? 'macos' : 'linux';
  final architecture = Platform.version.contains('arm64') ? 'arm64' : 'x64';
  return '$os-$architecture';
}

String _gitRevision() {
  final result = Process.runSync('git', ['rev-parse', 'HEAD']);
  return result.exitCode == 0 ? '${result.stdout}'.trim() : 'unknown';
}

Future<Map<String, Object?>> _fixtureIdentity(
  _Fixture fixture, {
  required bool execute,
}) async {
  final source = await _fileIdentity(fixture.path);
  if (fixture.imports.isNotEmpty) {
    source['imports'] = {
      for (final path in fixture.imports)
        path: (await _fileIdentity(path))['sha256'],
    };
  }
  if (fixture.hostTest case final String test when execute) {
    final files = {
      for (final path in [
        test,
        ...fixture.hostTestImports,
        if (!fixture.linksHost) 'test/support/native_assets.dart',
        if (fixture.hostProvider case final provider?) ...[
          provider.source,
          'tool/build_test_assets.dart',
        ],
      ])
        path: (await _fileIdentity(path))['sha256'],
    };
    source['hostExpectationFiles'] = files;
    source['hostExpectationSha256'] = sha256
        .convert(utf8.encode(jsonEncode(files)))
        .toString();
  }
  return source;
}

Future<Map<String, Object?>> _fileIdentity(String path) async {
  final file = File(path);
  return {
    'path': file.absolute.path,
    'bytes': await file.length(),
    'sha256': (await sha256.bind(file.openRead()).first).toString(),
  };
}

Map<String, String> _hostIdentity() => {
  'target': _hostTarget(),
  'operatingSystemVersion': Platform.operatingSystemVersion,
  'dart': Platform.version,
};

Future<Map<String, Object?>> _sourceIdentity({
  required bool built,
  required bool api,
}) async {
  final files = <File>[if (built) File('tool/build.dart')];
  for (final path in ['bin', 'lib', 'sdk', if (built) 'tool/src']) {
    await for (final entry in Directory(
      path,
    ).list(recursive: true, followLinks: false)) {
      if (entry is Link) {
        throw FileSystemException(
          'Cannot fingerprint symbolic source input',
          entry.path,
        );
      }
      if (entry is File) files.add(entry);
    }
  }
  for (final path in [
    if (api) _apiDriver,
    'pubspec.yaml',
    'pubspec.lock',
    '.dart_tool/package_config.json',
  ]) {
    if (File(path).existsSync()) files.add(File(path));
  }
  files.sort((a, b) => a.path.compareTo(b.path));
  final content = StringBuffer();
  final sdk = StringBuffer();
  for (final file in files) {
    final digest = (await _fileIdentity(file.path))['sha256'];
    final entry = '${file.path}\u0000$digest\n';
    content.write(entry);
    if (file.path.startsWith('sdk/')) sdk.write(entry);
  }
  return {
    'revision': _gitRevision(),
    'sha256': sha256.convert(utf8.encode('$content')).toString(),
    'files': files.length,
    'sdk': {
      'version': File('sdk/std/version').readAsStringSync().trim(),
      'revision': File('sdk/std/revision').readAsStringSync().trim(),
      'sha256': sha256.convert(utf8.encode('$sdk')).toString(),
    },
  };
}

String _environmentIdentity() {
  final names = Platform.environment.keys.toList()..sort();
  return sha256
      .convert(
        utf8.encode(
          [for (final name in names) '$name\u0000${Platform.environment[name]}']
              .join('\n'),
        ),
      )
      .toString();
}

String _resolveExecutable(String executable) {
  if (executable.contains('/')) {
    return File(executable).resolveSymbolicLinksSync();
  }
  for (final directory in (Platform.environment['PATH'] ?? '').split(':')) {
    final file = File('$directory/$executable');
    if (file.existsSync()) return file.resolveSymbolicLinksSync();
  }
  throw ArgumentError.value(executable, 'compiler', 'Executable not found');
}

String _safe(String value) => value.replaceAll(RegExp('[^a-zA-Z0-9_.-]'), '_');

final class const _Compiler(final String executable, final List<String> prefix);

const _usage = '''
Usage: dart run tool/bench.dart [options]

Compiles the fixed fixtures under tool/bench/fixtures and records wall time,
sampled direct-process RSS, output bytes and execution status in build/bench/latest.json.

Options:
  --only=a,b              Select fixtures. Shared host expectations include
                          checked_index, control_flow, generic_member_carriers,
                          generic_cell_storage and same_heap_finalizer.
                          checked_index_object and checked_index_static link a C host.
  --compiler=path         Use a compiler executable (default:
                          dart run bin/dartc.dart).
  --api                   Compile through the public Compiler API.
  --build                 Build build/bench/dartc and use it.
  --target=macos-arm64    Target passed to the compiler.
  --timeout=seconds       Compilation/build deadline (default: 120).
  --run-timeout=seconds   Deadline for each output execution (default: 120).
  --compile-only         Generate without execution; required for another target.
  --run-repeats=3         Executable runs per fixture; the median is reported.
  --output=path           Report path (default: build/bench/latest.json).
  --baseline=path         Compare selected fixtures against a successful report
                          for the same target.
  --max-time-growth=10    Allowed compile/run time growth percentage.
  --max-size-growth=5     Allowed output-size growth percentage.

Format 2 records microseconds, commands, binary/workload hashes and configuration.
Source and SDK identity are recorded for source and --build compilers; an external
--compiler has unknown source provenance. RSS is a 100 ms direct-process sample,
not a peak or a process-tree measurement. No execution means no runtime result.

For a POSIX wall-clock limit on the entire command and its process group:
  python3 tool/bench_guard.py 150 dart run tool/bench.dart --only=hello --timeout=120 --run-repeats=1
Allow time for the JSON report. If the outer deadline expires first, the report
may be incomplete or absent.
''';
