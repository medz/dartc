import 'dart:io';

import 'src/compiler_build.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length > 1) throw ArgumentError('Usage: build.dart [output]');
  final output = File(arguments.singleOrNull ?? 'build/dartc');
  await buildCompiler(output);
  stdout.writeln('Built ${output.path}.');
}
