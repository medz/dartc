import 'dart:ffi';
import 'dart:io';

import 'package:dartc/emit.dart';
import 'package:dartc/image.dart';
import 'package:dartc/lir.dart';
import 'package:test/test.dart';

import '../support/hosts.dart';

/// Why programs cannot run here, or null where they can.
final String? skipExecution = Abi.current() == Abi.macosArm64
    ? null
    : 'requires macOS ARM64';

/// Writes [module]'s program with entry `main` to [path].
void build(LirModule module, String path) {
  File(path).writeAsBytesSync(
    linkMacho(emitCode(module), entry: 'main', identifier: 'dartc-test'),
  );
  final result = Process.runSync('/bin/chmod', ['+x', path]);
  if (result.exitCode != 0) throw StateError('chmod: ${result.stderr}');
}

/// What Linux gives for programs that cannot be loaded.
const _unloadable = 127;

/// Builds and runs [module]; the result is negative if it crashes.
///
/// All hosts agree on what it is. A program still running after the deadline is
/// killed, so it fails its test.
Future<int> execute(LirModule module) async {
  final directory = Directory.systemTemp.createTempSync('dartc-image-');
  try {
    final codes = <int>[];
    for (final host in Host.all) {
      final path = '${directory.resolveSymbolicLinksSync()}/program';
      host.write(module, path, entry: 'main');
      const limit = Duration(seconds: 15);
      final code = (await host.run(path, limit: limit)).code;
      codes.add(code == _unloadable ? -1 : code);
    }
    // Systems differ in how programs that crash end.
    final told = {for (final code in codes) code < 0 ? -1 : code};
    expect(told, hasLength(1), reason: '$codes');
    return codes.first;
  } finally {
    directory.deleteSync(recursive: true);
  }
}
