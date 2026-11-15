import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Runs a fixed compiler benchmark suite and records time, RSS and output size.
///
/// The report is written to build/bench/latest.json. Machine-specific reports
/// stay under build/ and are never source inputs.
Future<void> main(List<String> arguments) async {
  final options = _Options.parse(arguments);
  if (options.help) {
    stdout.writeln(_usage);
    return;
  }
  final lock = await _benchLock();
  if (lock == null) return;
  try {
    var compiler = options.compiler == null
        ? _defaultCompiler()
        : _Compiler(options.compiler!, const []);
    if (options.build) {
      final built = File('build/bench/dartc').absolute.path;
      final build = await Process.run(Platform.resolvedExecutable, [
        'run',
        'tool/build.dart',
        built,
      ]);
      if (build.exitCode != 0) {
        stderr.writeln('${build.stdout}${build.stderr}');
        exitCode = build.exitCode;
        return;
      }
      compiler = _Compiler(built, const []);
    }
    final report = <String, Object?>{};
    final rows = <_Row>[];
    var failed = false;
    for (final fixture in fixtures) {
      if (options.only != null && !options.only!.contains(fixture.name)) {
        continue;
      }
      final row = await _run(fixture, compiler, options);
      rows.add(row);
      report[fixture.name] = row.toJson();
      failed |= row.failed;
    }
    final baseline = options.baseline == null
        ? null
        : jsonDecode(File(options.baseline!).readAsStringSync())
              as Map<String, dynamic>;
    final document = <String, Object?>{
      'created': DateTime.now().toUtc().toIso8601String(),
      'revision': _gitRevision(),
      'dart': Platform.version,
      'compiler': compiler,
      'target': options.target,
      'fixtures': report,
    };
    final output = File(options.output ?? 'build/bench/latest.json');
    await output.parent.create(recursive: true);
    await output.writeAsString(
      const JsonEncoder.withIndent('  ').convert(document),
    );
    _print(rows, baseline, options);
    if (baseline != null &&
        rows.any((row) => row.regressed(baseline, options))) {
      failed = true;
    }
    if (failed) exitCode = 1;
  } finally {
    if (lock.existsSync()) lock.deleteSync();
  }
}

const fixtures = <_Fixture>[
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

final class const _Fixture(
  final String name,
  final String path,
  final _Kind kind, {
  final bool run = false,
  final String? expected,
}) {
  String output(String target) {
    final directory = 'build/bench/${_safe(target)}';
    return switch (kind) {
      .executable => '$directory/$name',
      .shared =>
        target.contains('linux')
            ? '$directory/lib$name.so'
            : '$directory/lib$name.dylib',
    };
  }
}

enum _Kind { executable, shared }

final class _Options(
  final bool help,
  final Set<String>? only,
  final String? compiler,
  final String target,
  final String? output,
  final String? baseline,
  final Duration timeout,
  final double maxTimeGrowth,
  final double maxSizeGrowth,
  final bool build,
) {
  factory _Options.parse(List<String> arguments) {
    var help = false;
    Set<String>? only;
    String? compiler;
    var target = _hostTarget();
    String? output;
    String? baseline;
    var timeout = const Duration(seconds: 120);
    var maxTimeGrowth = 10.0;
    var maxSizeGrowth = 5.0;
    var build = false;
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
      } else if (argument.startsWith('--max-time-growth=')) {
        maxTimeGrowth = double.parse(
          argument.substring('--max-time-growth='.length),
        );
      } else if (argument.startsWith('--max-size-growth=')) {
        maxSizeGrowth = double.parse(
          argument.substring('--max-size-growth='.length),
        );
      } else if (argument == '--build') {
        build = true;
      } else {
        throw ArgumentError.value(argument, 'argument', 'Unknown option');
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
      maxTimeGrowth,
      maxSizeGrowth,
      build,
    );
  }
}

final class _Row(
  final String name,
  final int exitCode,
  final int elapsedMs,
  final int peakRssKiB,
  final int bytes,
  final bool timedOut,
  final String stdoutTail,
  final String stderrTail,
  final int? runMs,
  final int? runExitCode,
  final String runStdout,
  final bool runMatched,
) {
  bool get failed =>
      timedOut || exitCode != 0 || (runExitCode ?? 0) != 0 || !runMatched;

  Map<String, Object?> toJson() => {
    'exitCode': exitCode,
    'elapsedMs': elapsedMs,
    'peakRssKiB': peakRssKiB,
    'bytes': bytes,
    'timedOut': timedOut,
    'stdout': stdoutTail,
    'stderr': stderrTail,
    'runMs': runMs,
    'runExitCode': runExitCode,
    'runStdout': runStdout,
    'runMatched': runMatched,
  };

  bool regressed(Map<String, dynamic> baseline, _Options options) {
    final previous = baseline[name];
    if (previous is! Map) return false;
    final oldMs = previous['elapsedMs'];
    final oldBytes = previous['bytes'];
    if (oldMs is int && oldMs > 0) {
      final growth = (elapsedMs - oldMs) * 100 / oldMs;
      if (growth > options.maxTimeGrowth) return true;
    }
    if (oldBytes is int && oldBytes > 0) {
      final growth = (bytes - oldBytes) * 100 / oldBytes;
      if (growth > options.maxSizeGrowth) return true;
    }
    return false;
  }
}

Future<_Row> _run(
  _Fixture fixture,
  _Compiler compiler,
  _Options options,
) async {
  final output = fixture.output(options.target);
  await File(output).parent.create(recursive: true);
  final args = [
    ...compiler.prefix,
    fixture.path,
    '--kind',
    fixture.kind == .executable ? 'exe' : 'shared',
    '--target',
    options.target,
    '-o',
    output,
  ];
  final watch = Stopwatch()..start();
  final process = await Process.start(
    compiler.executable,
    args,
    workingDirectory: Directory.current.path,
  );
  var peakRss = 0;
  final stdoutBuffer = <String>[];
  final stderrBuffer = <String>[];
  final subscriptions = [
    process.stdout.transform(utf8.decoder).listen(stdoutBuffer.add),
    process.stderr.transform(utf8.decoder).listen(stderrBuffer.add),
  ];
  var timedOut = false;
  final rssWatch = Timer.periodic(const Duration(milliseconds: 100), (_) async {
    final rss = await _rssKiB(process.pid);
    if (rss > peakRss) peakRss = rss;
  });
  final exit = await process.exitCode.timeout(
    options.timeout,
    onTimeout: () {
      timedOut = true;
      process.kill(ProcessSignal.sigkill);
      return -1;
    },
  );
  rssWatch.cancel();
  await Future.wait(subscriptions.map((subscription) => subscription.cancel()));
  watch.stop();
  int? runMs;
  int? runExitCode;
  var runStdout = '';
  var runMatched = true;
  if (fixture.run && !timedOut && exit == 0) {
    final runWatch = Stopwatch()..start();
    final run = await Process.run(File(output).absolute.path, const []);
    runWatch.stop();
    runMs = runWatch.elapsedMilliseconds;
    runExitCode = run.exitCode;
    runStdout = '${run.stdout}';
    runMatched = fixture.expected == null || runStdout == fixture.expected;
  }
  final bytes = File(output).existsSync() ? File(output).lengthSync() : 0;
  return _Row(
    fixture.name,
    exit,
    watch.elapsedMilliseconds,
    peakRss,
    bytes,
    timedOut,
    _tail(stdoutBuffer),
    _tail(stderrBuffer),
    runMs,
    runExitCode,
    runStdout,
    runMatched,
  );
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
      lock.writeAsStringSync('$pid\n');
      return lock;
    } on FileSystemException {
      if (watch.elapsed > const Duration(minutes: 5)) {
        stderr.writeln('Another dartc benchmark holds $lock.');
        return null;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }
}

bool _processAlive(int pid) {
  final result = Process.runSync('kill', ['-0', '$pid']);
  return result.exitCode == 0;
}

Future<int> _rssKiB(int pid) async {
  final result = await Process.run('ps', ['-o', 'rss=', '-p', '$pid']);
  if (result.exitCode != 0) return 0;
  return int.tryParse('${result.stdout}'.trim()) ?? 0;
}

String _tail(List<String> lines) {
  final join = lines.join();
  const limit = 4000;
  return join.length <= limit ? join : join.substring(join.length - limit);
}

void _print(List<_Row> rows, Map<String, dynamic>? baseline, _Options options) {
  stdout.writeln(
    '${'fixture'.padRight(20)} ${'time'.padLeft(10)} ${'rss MiB'.padLeft(9)} '
    '${'bytes'.padLeft(10)} ${'run'.padLeft(8)} status',
  );
  for (final row in rows) {
    final previous = baseline?[row.name];
    final delta = previous is Map && previous['elapsedMs'] is int
        ? ' (${_signed(row.elapsedMs - (previous['elapsedMs'] as int))} ms)'
        : '';
    stdout.writeln(
      '${row.name.padRight(20)} '
      '${'${row.elapsedMs} ms'.padLeft(10)} '
      '${(row.peakRssKiB / 1024).toStringAsFixed(1).padLeft(9)} '
      '${'${row.bytes}'.padLeft(10)} '
      '${(row.runMs == null ? '-' : '${row.runMs} ms').padLeft(8)} '
      '${row.timedOut
          ? 'TIMEOUT'
          : row.failed
          ? 'FAIL(${row.exitCode}/${row.runExitCode})'
          : 'ok'}$delta',
    );
  }
  if (baseline != null) {
    stdout.writeln(
      'baseline growth limits: time +${options.maxTimeGrowth}%, '
      'size +${options.maxSizeGrowth}%',
    );
  }
}

String _signed(int value) => value >= 0 ? '+$value' : '$value';

_Compiler _defaultCompiler() {
  return _Compiler(Platform.resolvedExecutable, const [
    'run',
    'bin/dartc.dart',
  ]);
}

String _hostTarget() {
  final os = Platform.isMacOS ? 'macos' : 'linux';
  final architecture = Platform.version.contains('arm64') ? 'arm64' : 'x64';
  return '$os-$architecture';
}

String _gitRevision() {
  final result = Process.runSync('git', ['rev-parse', '--short', 'HEAD']);
  return result.exitCode == 0 ? '${result.stdout}'.trim() : 'unknown';
}

String _safe(String value) => value.replaceAll(RegExp('[^a-zA-Z0-9_.-]'), '_');

final class const _Compiler(final String executable, final List<String> prefix);

const _usage = '''
Usage: dart run tool/bench.dart [options]

Compiles the fixed fixtures under tool/bench/fixtures and records wall time,
child peak RSS, output bytes and execution status in build/bench/latest.json.

Options:
  --only=a,b              Run selected fixtures only.
  --compiler=path         Use a compiler executable (default:
                          dart run bin/dartc.dart).
  --build                 Build build/bench/dartc and use it.
  --target=macos-arm64    Target passed to the compiler.
  --timeout=seconds       Per-compilation limit (default: 120).
  --output=path           Report path (default: build/bench/latest.json).
  --baseline=path         Compare against a previous report.
  --max-time-growth=10    Allowed time growth percentage.
  --max-size-growth=5     Allowed output-size growth percentage.
''';
