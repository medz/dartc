import 'dart:io';
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
Future<Uint8List> compileProgram(String path, {required String sdk}) async {
  final source = await loadProgram(path, sdk: sdk);
  final code = emitArm64(lowerProgram(translateProgram(source)));
  final name = Uri.file(path).pathSegments.last;
  return linkMacho(code, entry: entrySymbol, identifier: name);
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
