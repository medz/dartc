@Tags(['assets', 'native'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

Future<void> checkIdentity(
  String command,
  String executable, {
  String? directory,
}) async {
  final process = await Process.start(
    command,
    [],
    workingDirectory: directory,
    includeParentEnvironment: false,
    environment: {'PATH': ''},
  );
  final output = process.stdout.transform(utf8.decoder).join();
  final errors = process.stderr.transform(utf8.decoder).join();
  final status = await process.exitCode;
  expect(status, 0, reason: '${await output}\n${await errors}');
  expect(await errors, isEmpty);
  expect(jsonDecode(await output), [
    process.pid,
    Platform.numberOfProcessors,
    Platform.localHostname,
    File(executable).resolveSymbolicLinksSync(),
  ]);
}

void main() {
  final executable = NativeAssets(Target.host())
      .file('compiler/entry_process_identity')
      .absolute
      .path;
  test('process identity describes the running target', () async {
    await checkIdentity(executable, executable);
  });
  test(
    'resolved executable follows a relative symlink to a long Unicode path',
    () async {
      final root = (Directory('build/test')..createSync(recursive: true))
          .createTempSync('process-identity-')
          .absolute;
      addTearDown(() => root.deleteSync(recursive: true));
      final nested = Directory(
        '${root.path}/${List.filled(5, '路径 ${'x' * 64}').join('/')}',
      )..createSync(recursive: true);
      final copy = File(executable).copySync('${nested.path}/程序');
      Link('${root.path}/启动')
          .createSync(copy.path.substring(root.path.length + 1));
      await checkIdentity('./启动', copy.path, directory: root.path);
    },
  );
}
