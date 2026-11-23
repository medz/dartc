import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dartc/emit.dart';
import 'package:dartc/image.dart';
import 'package:dartc/lower.dart';
import 'package:dartc/source.dart';
import 'package:dartc/translate.dart';

/// Compiles the program at [path] to a macOS ARM64 executable.
///
/// [sdk] is the Dart SDK whose libraries the program uses. Throws
/// [CompileFailure] if the program has an error or is not supported yet.
///
/// If [collectsAlways], the program collects before every allocation.
Future<Uint8List> compileProgram(
  String path, {
  required String sdk,
  bool collectsAlways = false,
}) async {
  final program = translateProgram(
    await loadProgram(path, sdk: sdk),
    runtime: await loadRuntime(sdk: sdk),
  );
  final code = emitArm64(lowerProgram(program, collectsAlways: collectsAlways));
  final name = Uri.file(path).pathSegments.last;
  return linkMacho(code, entry: entrySymbol, identifier: name);
}

final _runtimes = <String, Future<SourceProgram>>{};

/// The source of the runtime, against the Dart SDK at [sdk].
Future<SourceProgram> loadRuntime({required String sdk}) =>
    _runtimes[sdk] ??= _loadRuntime(sdk);

Future<SourceProgram> _loadRuntime(String sdk) async {
  final package = Uri.parse('package:dartc/heap.dart');
  final file = await Isolate.resolvePackageUri(package);
  if (file == null) throw StateError('$package is missing.');
  return loadProgram(file.toFilePath(), sdk: sdk);
}

/// Writes an executable file, replacing [output] only once it is complete.
void writeProgram(Uint8List program, String output) {
  final staged = File('$output.tmp-$pid');
  try {
    staged.writeAsBytesSync(program, flush: true);
    final result = Process.runSync('/bin/chmod', ['+x', staged.path]);
    if (result.exitCode != 0) {
      throw FileSystemException('${result.stderr}', staged.path);
    }
    staged.renameSync(output);
  } finally {
    if (staged.existsSync()) staged.deleteSync();
  }
}
