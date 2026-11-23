import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:dartc/emit.dart';
import 'package:dartc/image.dart';
import 'package:dartc/lir.dart';

/// Why programs cannot run here, or null where they can.
final String? skipExecution = Abi.current() == Abi.macosArm64
    ? null
    : 'requires macOS ARM64';

/// Writes [module]'s program with entry `main` to [path].
void build(LirModule module, String path) {
  File(path).writeAsBytesSync(
    linkMacho(emitArm64(module), entry: 'main', identifier: 'dartc-test'),
  );
  final result = Process.runSync('/bin/chmod', ['+x', path]);
  if (result.exitCode != 0) throw StateError('chmod: ${result.stderr}');
}

/// Builds and runs [module]; a negative result is the signal ending it.
///
/// A program still running after the deadline is killed, so it fails its test.
Future<int> execute(LirModule module) async {
  final directory = Directory.systemTemp.createTempSync('dartc-image-');
  try {
    final path = '${directory.path}/program';
    build(module, path);
    final process = await Process.start(path, const []);
    final timer = Timer(
      const Duration(seconds: 15),
      () => process.kill(.sigkill),
    );
    final code = await process.exitCode;
    timer.cancel();
    return code;
  } finally {
    directory.deleteSync(recursive: true);
  }
}
