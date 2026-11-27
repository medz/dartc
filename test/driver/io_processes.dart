/// Programs that start others, and listen for signals.
const processPrograms = {
  'processes': r'''
import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> attempt(String name, FutureOr<Object?> Function() work) async {
  try {
    print('$name: ${await work()}');
  } catch (e) {
    print('$name fails: $e');
  }
}

String show(ProcessResult r) => '${r.exitCode} ${jsonEncode(r.stdout)} ${jsonEncode(r.stderr)}';

int openFiles() => Directory(Platform.isMacOS ? '/dev/fd' : '/proc/self/fd').listSync().length;

Future<void> main() async {
  await attempt('run', () async => show(await Process.run('echo', ['a', 'b c'])));
  await attempt('sync', () => show(Process.runSync('sh', ['-c', 'echo out; echo err >&2; exit 3'])));
  final files = openFiles();
  await attempt('missing', () async => show(await Process.run('no_such_program_x', ['1'])));
  await attempt('missing sync', () => show(Process.runSync('no_such_program_x', [])));
  print('failed starts release pipes: ${openFiles() == files}');
  await attempt('dir', () async => show(await Process.run('pwd', [], workingDirectory: '/')));
  await attempt('bad dir', () async => show(await Process.run('pwd', [], workingDirectory: '/nonexistent_x')));
  await attempt('env', () async => show(await Process.run('sh', ['-c', r'echo $FOO'], environment: {'FOO': 'bar'})));
  await attempt('no env', () async => show(await Process.run('/usr/bin/env', [], includeParentEnvironment: false, environment: {'A': '1'})));
  await attempt('shell', () async => show(await Process.run('echo', ['a  b', "it's"], runInShell: true)));
  await attempt('bytes', () async => (await Process.run('printf', ['\\377'], stdoutEncoding: null)).stdout);
  final p = await Process.start('cat', []);
  final echoed = p.stdout.transform(utf8.decoder).join();
  const lots = 262144;
  final input = 'x' * lots;
  p.stdin.write(input);
  await p.stdin.close();
  print('full duplex: ${await echoed == input}');
  print(await p.exitCode);
  final q = await Process.start('sleep', ['10']);
  print(q.kill());
  print(await q.exitCode);
  print(q.kill());
  final r = await Process.start('sh', ['-c', 'exit 7'], mode: ProcessStartMode.inheritStdio);
  print(await r.exitCode);
  final d = await Process.start('sh', ['-c', 'echo detached output'], mode: ProcessStartMode.detached);
  await attempt('detached exit', () => d.exitCode);
  print(d.pid > 0);
  final s = await Process.start('sh', ['-c', 'echo hi'], mode: ProcessStartMode.detachedWithStdio);
  print(await s.stdout.transform(utf8.decoder).join());
  await attempt('killPid', () => Process.killPid(999999));
  await attempt('kill9', () async {
    final k = await Process.start('sleep', ['10']);
    k.kill(ProcessSignal.sigkill);
    return k.exitCode;
  });
  await attempt('watch', () => ProcessSignal.sigkill.watch());
  final signal = ProcessSignal.sigusr1.watch().first;
  await Process.run('/bin/kill', ['-USR1', '$pid']);
  print('got ${await signal}');
  print('end');
}
''',
  'process executables': r'''
import 'dart:convert';
import 'dart:io';

void script(String path, String text, {bool executable = true}) {
  File(path).writeAsStringSync('#!/bin/sh\necho $text\n');
  final mode = executable ? '755' : '644';
  if (Process.runSync('/bin/chmod', [mode, path]).exitCode != 0) {
    throw StateError('chmod failed');
  }
}

Future<void> main() async {
  final arguments = ['first'];
  final starting = Process.start('/bin/echo', arguments);
  arguments[0] = 'second';
  final child = await starting;
  print((await child.stdout.transform(utf8.decoder).join()).trim());
  print(await child.exitCode);

  Directory('work/bin').createSync(recursive: true);
  Directory('work/blocked').createSync();
  script('helper', 'parent');
  script('work/helper', 'child');
  script('work/bin/helper', 'child PATH');
  script('work/blocked/helper', 'blocked', executable: false);

  final relative = await Process.run('./helper', [], workingDirectory: 'work');
  print(relative.stdout.trim());
  final fromPath = Process.runSync(
    Platform.isLinux ? 'helper' : './bin/helper',
    [],
    workingDirectory: 'work',
    environment: {'PATH': 'blocked:bin'},
  );
  print(fromPath.stdout.trim());
  try {
    Process.runSync(
      Platform.isLinux ? 'helper' : './blocked/helper',
      [],
      workingDirectory: 'work',
      environment: {'PATH': 'blocked'},
    );
  } on ProcessException catch (error) {
    print(error.errorCode);
  }
}
''',
};
