import 'dart:io';

Future<void> main(List<String> arguments) async {
  final result = await Process.run(File('compiler').absolute.path, arguments);
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  exitCode = result.exitCode;
}
