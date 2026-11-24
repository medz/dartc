import 'dart:io';

import 'package:dartc/driver.dart';
import 'package:dartc/optimize.dart';

/// The least time of some runs of [program], in milliseconds, and what it
/// prints.
(int, String) _run(String program, {int runs = 3}) {
  var least = 1 << 40, output = '';
  for (var i = 0; i < runs; i++) {
    final watch = Stopwatch()..start();
    final result = Process.runSync(program, const []);
    final time = watch.elapsedMilliseconds;
    if (time < least) least = time;
    output = '${result.stdout}';
    if (result.exitCode != 0) throw StateError('$program: ${result.stderr}');
  }
  return (least, output);
}

/// Measures the programs in `tool/bench/programs`, or those that are named,
/// against the official compiler. Optimizations called `-name` are left out.
Future<void> main(List<String> arguments) async {
  final names = [
    for (final argument in arguments)
      if (!argument.startsWith('-')) argument,
  ];
  final optimizations = {
    for (final optimization in Optimization.values)
      if (!arguments.contains('-${optimization.name}')) optimization,
  };
  final directory = Directory.systemTemp.createTempSync('dartc-measure-');
  final files = Directory('tool/bench/programs').listSync().whereType<File>();
  final paths = [for (final file in files) file.path]..sort();
  print('program      compiled  official   ratio      bytes  compiling');
  for (final path in paths) {
    final name = path.split('/').last.split('.').first;
    if (names.isNotEmpty && !names.contains(name)) continue;
    final program = '${directory.path}/$name';
    final watch = Stopwatch()..start();
    final bytes = await compileProgram(
      path,
      CompileOptions(optimizations: optimizations),
    );
    final compiling = watch.elapsedMilliseconds;
    writeProgram(bytes, program);
    Process.runSync(Platform.resolvedExecutable, [
      'compile',
      'exe',
      path,
      '-o',
      '$program.official',
    ]);
    final (time, output) = _run(program);
    final (official, expected) = _run('$program.official');
    final isSame = output == expected ? '' : '  DIFFERENT OUTPUT';
    print(
      '${name.padRight(12)} ${'$time'.padLeft(5)} ms ${'$official'.padLeft(6)} '
      'ms ${(time / official).toStringAsFixed(2).padLeft(7)} '
      '${'${bytes.length}'.padLeft(10)} ${'$compiling'.padLeft(7)} ms$isSame',
    );
  }
  directory.deleteSync(recursive: true);
}
