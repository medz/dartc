import 'dart:io';
import 'dart:isolate';

String hostRead(String path) => File(path).readAsStringSync();

String? hostReadIfExists(String path) {
  try {
    return hostRead(path);
  } on FileSystemException catch (error) {
    final code = error.osError?.errorCode;
    if (code == 2 || code == 20) return null;
    rethrow;
  }
}

String hostCurrentDirectory() => Directory.current.path;

void hostWrite(String path, List<int> bytes) {
  File(path).parent.createSync(recursive: true);
  File(path).writeAsBytesSync(bytes);
}

Never hostExit(int status) => exit(status);

int hostTarget() => Platform.isLinux ? 1 : 0;

String hostStdPath() {
  final asset = Isolate.resolvePackageUriSync(
    Uri.parse('package:dartc/src/runtime.dart'),
  );
  if (asset != null) return asset.toFilePath();
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
