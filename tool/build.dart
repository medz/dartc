import 'dart:io';

import 'package:dartc/driver.dart';
import 'package:dartc/source.dart';

const _usage = 'Usage: dart run tool/build.dart [--with=<dartc>] [output]';

/// Builds the compiler as one program that needs no other files, with the
/// official compiler or with one that was built here.
Future<void> main(List<String> arguments) async {
  final withOption = arguments.where((a) => a.startsWith('--with='));
  final rest = arguments.where((a) => !a.startsWith('-'));
  if (withOption.length > 1 ||
      rest.length > 1 ||
      withOption.length + rest.length != arguments.length) {
    stderr.writeln(_usage);
    exit(64);
  }
  final own = withOption.firstOrNull?.substring('--with='.length);
  final output = File(rest.firstOrNull ?? 'build/dartc');
  output.parent.createSync(recursive: true);
  // Generated files are found by the package's own configuration there.
  final directory = Directory('.dart_tool/dartc')..createSync(recursive: true);
  final main = File('${directory.path}/main.dart')
    ..writeAsStringSync('''
import 'dart:io';

// The rest of the driver is for where the libraries are files.
import 'package:dartc/src/driver/command.dart';
import 'package:dartc/source.dart';

const _sdk = '${packSdkFiles(await packagedSdkFiles())}';

Future<void> main(List<String> arguments) async {
  exitCode = await runCommand(
    arguments,
    output: stdout,
    errors: stderr,
    sdk: () async => unpackSdkFiles(_sdk),
  );
}
''');
  final result = own == null
      ? Process.runSync(Platform.resolvedExecutable, [
          'compile',
          'exe',
          main.path,
          '-o',
          output.path,
        ])
      : Process.runSync(own, [main.path, '-o', output.path]);
  if (result.exitCode != 0) {
    stderr.write('${result.stdout}${result.stderr}');
    exit(1);
  }
  stdout.writeln('Built ${output.path}.');
}
