import 'dart:io';

import 'src/embedded.dart';

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
  final main = await writeEmbedded(
    'main',
    '''
import 'dart:io';

// The rest of the driver is for where the libraries are files.
import 'package:dartc/src/driver/command.dart';
''',
    '''
Future<void> main(List<String> arguments) async {
  exitCode = await runCommand(
    arguments,
    output: stdout,
    errors: stderr,
    sdk: () async => sdkFiles,
  );
}
''',
  );
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
