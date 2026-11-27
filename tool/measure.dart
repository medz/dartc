import 'dart:convert';
import 'dart:io';

import 'package:dartc/optimize.dart';

import 'src/embedded.dart';

const _usage = '''
Usage: dart run tool/measure.dart [names] [-<optimization>] [--self] [--update]

Measures the programs in tool/bench/programs, or those that are named, and
dartc itself: the dartc that dartc built compiling hello, and with --self or
the name dartc-self compiling itself, which takes minutes. Optimizations
called -<name> are left out. Shows what changed since tool/bench/baseline.json,
which --update writes instead.''';

const _baseline = 'tool/bench/baseline.json';

/// What is measured of a workload: run time against the official compiler,
/// bytes of the program, and the time and most memory that compiling it took.
typedef Measures = ({double ratio, int bytes, int compiling, int memory});

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
    final measured = <String, Measures>{};
    stdout.writeln('Building the compiler with the official compiler.');
    _source = await _writeCompiler();
    _check(
      Process.runSync(Platform.resolvedExecutable, [
        'compile',
        'exe',
        _source.path,
        '-o',
        _compiler,
      ]),
    );
    stdout.writeln(_header);
    final only = names.isNotEmpty;
    for (final path in paths) {
      final name = path.split('/').last.split('.').first;
      if (only && !names.contains(name)) continue;
      measured[name] = _program(path, name);
      _report(name, measured[name]!);
    }
    if (!only || names.contains('dartc') || self) {
      for (final MapEntry(:key, :value) in _itself(self: self).entries) {
        measured[key] = value;
        _report(key, value);
      }
    }
    return measured;
  }

  Measures _program(String path, String name) {
    final program = '$_directory/$name';
    final (compiling, memory) = _compile(_compiler, path, program);
    _check(
      Process.runSync(Platform.resolvedExecutable, [
        'compile',
        'exe',
        path,
        '-o',
        '$program.official',
      ]),
    );
    final (time, output) = _run(program, const []);
    final (official, expected) = _run('$program.official', const []);
    if (output != expected) throw StateError('$name prints something else.');
    return (
      ratio: time / official,
      bytes: File(program).lengthSync(),
      compiling: compiling,
      memory: memory,
    );
  }

  /// The compiler that the compiler built, compiling hello and if [self]
  /// itself, against the one the official compiler built.
  Map<String, Measures> _itself({required bool self}) {
    final own = '$_directory/own';
    stdout.writeln('Building the compiler with itself.');
    final (compiling, memory) = _compile(_compiler, _source.path, own);
    final hello = File('$_directory/hello.dart')
      ..writeAsStringSync("void main() => print('hello');\n");
    final toHello = _arguments(hello.path, '$_directory/hello');
    final itself = _arguments(_source.path, '$_directory/third');
    Measures against(int time, int official) => (
      ratio: time / official,
      bytes: File(own).lengthSync(),
      compiling: compiling,
      memory: memory,
    );

    return {
      'dartc': against(_run(own, toHello).$1, _run(_compiler, toHello).$1),
      if (self)
        'dartc-self': against(
          _run(own, itself, runs: 1).$1,
          _run(_compiler, itself, runs: 1).$1,
        ),
    };
  }

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

  /// The least time of some runs of [program], in milliseconds, and what it
  /// prints.
  (int, String) _run(String program, List<String> arguments, {int runs = 3}) {
    var least = 1 << 40, output = '';
    for (var i = 0; i < runs; i++) {
      final watch = Stopwatch()..start();
      final result = _check(Process.runSync(program, arguments));
      final time = watch.elapsedMilliseconds;
      if (time < least) least = time;
      output = '${result.stdout}';
    }
    return (least, output);
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
    'workload      ratio  change      bytes  change  compiling  change'
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
String _row(Measures now, Measures? before) {
  String change(num now, num? before) => before == null || before == 0
      ? ''
      : '${now >= before ? '+' : ''}'
            '${(100 * (now - before) / before).toStringAsFixed(1)}%';
  return [
    now.ratio.toStringAsFixed(2).padLeft(6),
    change(now.ratio, before?.ratio).padLeft(7),
    '${now.bytes}'.padLeft(10),
    change(now.bytes, before?.bytes).padLeft(7),
    '${now.compiling} ms'.padLeft(10),
    change(now.compiling, before?.compiling).padLeft(7),
    '${now.memory >> 20} MB'.padLeft(7),
    change(now.memory, before?.memory).padLeft(7),
  ].join(' ');
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
          bytes: bytes,
          compiling: compiling,
          memory: memory,
        ),
  };
}

void _write(Map<String, Measures> measures) {
  final names = measures.keys.toList()..sort();
  final json = {
    for (final name in names)
      name: {
        'ratio': double.parse(measures[name]!.ratio.toStringAsFixed(3)),
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
