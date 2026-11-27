import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dartc/optimize.dart';

import 'src/embedded.dart';

const _usage = '''
Usage: dart run tool/measure.dart [names] [-<optimization>] [--self] [--update]

Measures the programs in tool/bench/programs, or those that are named, and
dartc itself: the dartc that dartc built compiling hello, and with --self or
the name dartc-self compiling itself, which takes minutes. Optimizations
called -<name> are left out. Shows what changed since tool/bench/baseline.json,
which --update writes instead.

The ratio is the median of rounds that run ours and the official program in
turn, and ± the spread is where that median lies with a chance of about 95%.
A change of the ratio in parentheses is noise: the ranges of now and of the
baseline meet.''';

const _baseline = 'tool/bench/baseline.json';

/// What is measured of a workload: run time against the official compiler and
/// how far that spreads, bytes of the program, and the time and most memory
/// that compiling it took.
///
/// The spread is a fraction of the ratio, or null if one round was run.
typedef Measures = ({
  double ratio,
  double? spread,
  int bytes,
  int compiling,
  int memory,
});

/// How much longer a program takes than the official one, and how far the
/// ratios of rounds spread.
typedef _Timed = ({double ratio, double? spread});

/// A program of ours and the official one to time against each other, with
/// what is measured of compiling ours, whether their outputs are compared,
/// and how many rounds it may take.
typedef _Workload = ({
  String name,
  String program,
  String official,
  List<String> arguments,
  bool isChecked,
  int most,
  int bytes,
  int compiling,
  int memory,
});

/// Measures run time, size and compiling, and keeps or compares a baseline.
Future<void> main(List<String> arguments) async {
  final optimizations = {...Optimization.values};
  final names = <String>{};
  var update = false, self = false;
  for (final argument in arguments) {
    if (argument == '--update') {
      update = true;
    } else if (argument == '--self') {
      self = true;
    } else if (argument.startsWith('-')) {
      final name = argument.substring(1);
      final left = Optimization.values.where((o) => o.name == name);
      if (left.isEmpty) return _fail();
      optimizations.remove(left.single);
    } else {
      names.add(argument);
    }
  }
  if (update && optimizations.length != Optimization.values.length) {
    return _fail('The baseline has all optimizations.');
  }
  final directory = Directory.systemTemp.createTempSync('dartc-measure-');
  try {
    final measured = await _Measuring(
      directory.path,
      optimizations,
    ).measure(names, self: self || names.contains('dartc-self'));
    final baseline = _read();
    if (update) {
      _write({...baseline, ...measured});
    } else {
      _show(measured, baseline);
    }
  } finally {
    directory.deleteSync(recursive: true);
  }
}

void _fail([String message = _usage]) {
  stderr.writeln(message);
  exitCode = 64;
}

final class _Measuring(final String _directory, final Set<Optimization> _uses) {
  /// The compiler that the official compiler built, which tells how long it
  /// took and the most memory it used.
  late final String _compiler = '$_directory/compiler';
  late final File _source;

  /// Measures the workloads that [names] has, or all if it has none, and
  /// whether the compiler compiles itself as [self] tells.
  Future<Map<String, Measures>> measure(
    Set<String> names, {
    required bool self,
  }) async {
    final files = Directory('tool/bench/programs').listSync().whereType<File>();
    final paths = [for (final file in files) file.path]..sort();
    stdout.writeln('Building the compiler with the official compiler.');
    _source = await _writeCompiler();
    _officially(_source.path, _compiler);
    final only = names.isNotEmpty;
    final workloads = [
      for (final path in paths)
        if (path.split('/').last.split('.').first case final name
            when !only || names.contains(name))
          _workload(path, name),
      if (!only || names.contains('dartc') || self) ..._itself(self: self),
    ];
    stdout.writeln('Running ${workloads.length} workloads in turn.');
    final timed = _timeAll([
      for (final workload in workloads)
        if (workload.most > 1) workload,
    ]);
    stdout.writeln(_header);
    final measured = <String, Measures>{};
    for (final workload in workloads) {
      final name = workload.name;
      final (:ratio, :spread) = timed[name] ?? _inOneGo(workload);
      measured[name] = (
        ratio: ratio,
        spread: spread,
        bytes: workload.bytes,
        compiling: workload.compiling,
        memory: workload.memory,
      );
      _report(name, measured[name]!);
    }
    return measured;
  }

  /// Compiles the program at [path] with both compilers.
  _Workload _workload(String path, String name) {
    final program = '$_directory/$name';
    final (compiling, memory) = _compile(_compiler, path, program);
    _officially(path, '$program.official');
    return (
      name: name,
      program: program,
      official: '$program.official',
      arguments: const [],
      isChecked: true,
      most: _most,
      bytes: File(program).lengthSync(),
      compiling: compiling,
      memory: memory,
    );
  }

  /// The compiler that the compiler built, compiling hello and if [self]
  /// itself, against the one the official compiler built.
  List<_Workload> _itself({required bool self}) {
    final own = '$_directory/own';
    stdout.writeln('Building the compiler with itself.');
    final (compiling, memory) = _compile(_compiler, _source.path, own);
    final hello = File('$_directory/hello.dart')
      ..writeAsStringSync("void main() => print('hello');\n");
    _Workload compiles(String name, List<String> arguments, int most) => (
      name: name,
      program: own,
      official: _compiler,
      arguments: arguments,
      isChecked: false,
      most: most,
      bytes: File(own).lengthSync(),
      compiling: compiling,
      memory: memory,
    );
    return [
      compiles('dartc', _arguments(hello.path, '$_directory/hello'), _most),
      // This takes minutes, so it runs once, after compiling hello warmed both.
      if (self)
        compiles(
          'dartc-self',
          _arguments(_source.path, '$_directory/third'),
          1,
        ),
    ];
  }

  void _officially(String source, String output) => _check(
    Process.runSync(Platform.resolvedExecutable, [
      'compile',
      'exe',
      source,
      '-o',
      output,
    ]),
  );

  /// Compiles [source] to [output] with [compiler], and gives the time it took
  /// in milliseconds and the most bytes of memory that it used.
  (int, int) _compile(String compiler, String source, String output) {
    final result = _check(
      Process.runSync(compiler, _arguments(source, output)),
    );
    final [time, memory] = '${result.stdout}'.trim().split(' ');
    return (int.parse(time), int.parse(memory));
  }

  /// What makes a compiler that [_writeCompiler] wrote compile [source] to
  /// [output] with the optimizations that are used.
  List<String> _arguments(String source, String output) => [
    source,
    output,
    for (final optimization in _uses) optimization.name,
  ];

  /// The fewest and most rounds that run both programs of a workload, and the
  /// spread below which more are not needed.
  static const _fewest = 5, _most = 15, _enough = 0.01;

  /// How much longer each of [workloads] takes than the official program.
  ///
  /// Each round runs every workload that still needs it once, so that the
  /// rounds of each are spread over the whole time, and changes of the machine
  /// over minutes show in how far they spread. Those of a workload stop when
  /// its ratios spread less than [_enough], or after [_most].
  ///
  /// Each program is run once before, as the first run of a new file also
  /// waits for checks of the system.
  Map<String, _Timed> _timeAll(List<_Workload> workloads) {
    for (final workload in workloads) {
      _run(workload.program, workload.arguments);
      _run(workload.official, workload.arguments);
    }
    final ratios = {
      for (final workload in workloads) workload.name: <double>[],
    };
    var left = workloads;
    while (left.isNotEmpty) {
      for (final workload in left) {
        final of = ratios[workload.name]!;
        of.add(_round(workload, isFirst: of.length.isEven));
      }
      left = [
        for (final workload in left)
          if (ratios[workload.name]! case final of
              when of.length < _most &&
                  (of.length < _fewest || _spreadOf(of)! >= _enough))
            workload,
      ];
    }
    return {
      for (final MapEntry(:key, :value) in ratios.entries) key: _timed(value),
    };
  }

  /// Times [workload] in its rounds one after another, unwarmed.
  _Timed _inOneGo(_Workload workload) => _timed([
    for (var i = 0; i < workload.most; i++) _round(workload, isFirst: i.isEven),
  ]);

  /// How much longer the program of [workload] took than the official one in
  /// a round, which runs it first if [isFirst] and else last, so that the
  /// order does not favor one.
  double _round(_Workload workload, {required bool isFirst}) {
    final _Workload(:program, :official, :arguments) = workload;
    final before = isFirst ? null : _run(official, arguments);
    final own = _run(program, arguments);
    final other = before ?? _run(official, arguments);
    if (workload.isChecked && own.output != other.output) {
      throw StateError('${workload.name} prints something else.');
    }
    return own.time / other.time;
  }

  static _Timed _timed(List<double> ratios) {
    final sorted = [...ratios]..sort();
    return (ratio: sorted[sorted.length ~/ 2], spread: _spreadOf(sorted));
  }

  /// Half the width of the range in which the median of [ratios] lies with
  /// a chance of about 95%, as a fraction of it, or null if there is one.
  ///
  /// That range is between the ratios that have as many below and above as a
  /// count of [ratios] coins shows heads, give or take twice the deviation of
  /// that count. It knows nothing of how ratios are distributed, and is wider
  /// for fewer rounds.
  static double? _spreadOf(List<double> ratios) {
    if (ratios.length < 2) return null;
    final sorted = [...ratios]..sort();
    final n = sorted.length;
    final outside = max(0, (n - 1.96 * sqrt(n)) ~/ 2);
    final width = sorted[n - 1 - outside] - sorted[outside];
    return width / 2 / sorted[n ~/ 2];
  }

  /// How long one run of [program] took, in microseconds, and what it printed.
  ({int time, String output}) _run(String program, List<String> arguments) {
    final watch = Stopwatch()..start();
    final result = _check(Process.runSync(program, arguments));
    return (time: watch.elapsedMicroseconds, output: '${result.stdout}');
  }
}

ProcessResult _check(ProcessResult result) {
  if (result.exitCode == 0) return result;
  throw StateError('${result.stdout}${result.stderr}');
}

/// A compiler that compiles its first argument to its second with the
/// optimizations named after them, and prints how long that took and the most
/// memory it used.
Future<File> _writeCompiler() => writeEmbedded(
  'measure',
  '''
import 'dart:io';
import 'dart:math';

import 'package:dartc/driver.dart';
import 'package:dartc/optimize.dart';
''',
  '''
Future<void> main(List<String> arguments) async {
  final watch = Stopwatch()..start();
  final [source, output, ...names] = arguments;
  final options = CompileOptions(
    target: hostTarget!,
    optimizations: {
      for (final optimization in Optimization.values)
        if (names.contains(optimization.name)) optimization,
    },
  );
  final sdk = sdkFor(options.target, sdkFiles);
  writeProgram(await buildProgram(source, sdk, options), output);
  print('\${watch.elapsedMilliseconds} \${ProcessInfo.maxRss}');
}
''',
);

const _header =
    'workload      ratio  spread   change      bytes  change  compiling  change'
    '  memory  change';

void _report(String name, Measures measures) =>
    stdout.writeln('${name.padRight(12)} ${_row(measures, null)}');

void _show(Map<String, Measures> measured, Map<String, Measures> baseline) {
  if (baseline.isEmpty) return stdout.writeln('\n$_baseline has nothing.');
  stdout.writeln('\nAgainst $_baseline:\n$_header');
  for (final MapEntry(:key, :value) in measured.entries) {
    stdout.writeln('${key.padRight(12)} ${_row(value, baseline[key])}');
  }
}

/// [now] in columns, with how much it changed since [before] if known.
///
/// A change of the ratio is in parentheses when it is noise: the ranges that
/// the spreads give meet.
String _row(Measures now, Measures? before) {
  String change(num now, num? before) => before == null || before == 0
      ? ''
      : '${now >= before ? '+' : ''}'
            '${(100 * (now - before) / before).toStringAsFixed(1)}%';
  String percent(double? fraction) =>
      fraction == null ? '' : '±${(100 * fraction).toStringAsFixed(1)}%';
  var ratio = change(now.ratio, before?.ratio);
  if (before != null && _isNoise(now, before)) ratio = '($ratio)';
  return [
    now.ratio.toStringAsFixed(2).padLeft(6),
    percent(now.spread).padLeft(7),
    ratio.padLeft(8),
    '${now.bytes}'.padLeft(10),
    change(now.bytes, before?.bytes).padLeft(7),
    '${now.compiling} ms'.padLeft(10),
    change(now.compiling, before?.compiling).padLeft(7),
    '${now.memory >> 20} MB'.padLeft(7),
    change(now.memory, before?.memory).padLeft(7),
  ].join(' ');
}

/// Whether the ratios of [now] and [before] may well be the same: whether
/// the ranges that their spreads give meet. Without both spreads, that is not
/// known.
bool _isNoise(Measures now, Measures before) {
  final (spread, other) = (now.spread, before.spread);
  if (spread == null || other == null) return false;
  final change = (now.ratio - before.ratio).abs();
  return change <= spread * now.ratio + other * before.ratio;
}

Map<String, Measures> _read() {
  final file = File(_baseline);
  if (!file.existsSync()) return {};
  final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  return {
    for (final MapEntry(:key, :value) in json.entries)
      if (value case {
        'ratio': final num ratio,
        'bytes': final int bytes,
        'compiling': final int compiling,
        'memory': final int memory,
      })
        key: (
          ratio: ratio.toDouble(),
          // Older baselines have none.
          spread: (value['spread'] as num?)?.toDouble(),
          bytes: bytes,
          compiling: compiling,
          memory: memory,
        ),
  };
}

double? _rounded(double? fraction) =>
    fraction == null ? null : double.parse(fraction.toStringAsFixed(4));

void _write(Map<String, Measures> measures) {
  final names = measures.keys.toList()..sort();
  final json = {
    for (final name in names)
      name: {
        'ratio': double.parse(measures[name]!.ratio.toStringAsFixed(3)),
        'spread': ?_rounded(measures[name]!.spread),
        'bytes': measures[name]!.bytes,
        'compiling': measures[name]!.compiling,
        'memory': measures[name]!.memory,
      },
  };
  File(
    _baseline,
  ).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(json)}\n');
  stdout.writeln('Wrote $_baseline.');
}
