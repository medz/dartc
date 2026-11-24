import 'dart:io';

import 'package:dartc/driver.dart';
import 'package:dartc/source.dart';

/// Builds the compiler as one program that needs no other files.
Future<void> main(List<String> arguments) async {
  if (arguments.length > 1) {
    stderr.writeln('Usage: dart run tool/build.dart [output]');
    exit(64);
  }
  final output = File(arguments.firstOrNull ?? 'build/dartc');
  output.parent.createSync(recursive: true);
  // Generated files are found by the package's own configuration there.
  final directory = Directory('.dart_tool/dartc')..createSync(recursive: true);
  final main = File('${directory.path}/main.dart')
    ..writeAsStringSync('''
import 'dart:io';

import 'package:dartc/driver.dart';
import 'package:dartc/source.dart';

const _sdk = '${packSdkFiles(await packagedSdkFiles())}';

Future<void> main(List<String> arguments) async {
  exitCode = await runCommand(
    arguments,
    output: stdout,
    errors: stderr,
    sdk: unpackSdkFiles(_sdk),
  );
}
''');
  final result = Process.runSync(Platform.resolvedExecutable, [
    'compile',
    'exe',
    main.path,
    '-o',
    output.path,
  ]);
  if (result.exitCode != 0) {
    stderr.write('${result.stdout}${result.stderr}');
    exit(1);
  }
  stdout.writeln('Built ${output.path}.');
}
