import 'dart:io';

String hostRead(String path) => File(path).readAsStringSync();

void hostWrite(String path, List<int> bytes) {
  File(path).parent.createSync(recursive: true);
  File(path).writeAsBytesSync(bytes);
}

Never hostExit(int status) => exit(status);

int hostTarget() => Platform.isLinux ? 1 : 0;

String hostStdPath() {
  var folder = File.fromUri(Platform.script).absolute.parent.path;
  while (folder != '/') {
    final candidate = folder + '/lib/src/runtime.dart';
    if (File(candidate).existsSync()) return candidate;
    folder = Directory(folder).parent.path;
  }
  throw StateError('Cannot locate the dartc runtime source; use --std <file>');
}

Never hostFinish(String path, int outputTarget) {
  final mode = Process.runSync('/bin/chmod', ['+x', path]);
  if (mode.exitCode != 0) stderr.write(mode.stderr);
  exit(mode.exitCode);
}
