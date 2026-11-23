import 'dart:io';

import 'package:dartc/driver.dart';
import 'package:dartc/source.dart';

/// Compiles a Dart program with the new compiler.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln('Usage: dart run tool/compile.dart <source> <output>');
    exit(64);
  }
  final [source, output] = arguments;
  try {
    writeProgram(await compileProgram(source), output);
  } on CompileFailure catch (failure) {
    stderr.writeln(failure);
    exit(1);
  }
}
