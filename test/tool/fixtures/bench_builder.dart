import 'dart:io';

Future<void> main(List<String> arguments) async {
  final output = File(arguments.single);
  await output.parent.create(recursive: true);
  await File('compiler').copy(output.path);
  final chmod = await Process.run('chmod', ['+x', output.path]);
  exitCode = chmod.exitCode;
}
