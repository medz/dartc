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

Future<void> main() async {
  await attempt('run', () async => show(await Process.run('echo', ['a', 'b c'])));
  await attempt('sync', () => show(Process.runSync('sh', ['-c', 'echo out; echo err >&2; exit 3'])));
  await attempt('missing', () async => show(await Process.run('no_such_program_x', ['1'])));
  await attempt('missing sync', () => show(Process.runSync('no_such_program_x', [])));
  await attempt('dir', () async => show(await Process.run('pwd', [], workingDirectory: '/')));
  await attempt('bad dir', () async => show(await Process.run('pwd', [], workingDirectory: '/nonexistent_x')));
  await attempt('env', () async => show(await Process.run('sh', ['-c', r'echo $FOO'], environment: {'FOO': 'bar'})));
  await attempt('no env', () async => show(await Process.run('/usr/bin/env', [], includeParentEnvironment: false, environment: {'A': '1'})));
  await attempt('shell', () async => show(await Process.run('echo', ['a  b', "it's"], runInShell: true)));
  await attempt('bytes', () async => (await Process.run('printf', ['\\377'], stdoutEncoding: null)).stdout);
  final p = await Process.start('cat', []);
  p.stdin.writeln('hello');
  await p.stdin.close();
  print(await p.stdout.transform(utf8.decoder).join());
  print(await p.exitCode);
  final q = await Process.start('sleep', ['10']);
  print(q.kill());
  print(await q.exitCode);
  print(q.kill());
  final r = await Process.start('sh', ['-c', 'exit 7'], mode: ProcessStartMode.inheritStdio);
  print(await r.exitCode);
  final d = await Process.start('true', [], mode: ProcessStartMode.detached);
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
  final sub = ProcessSignal.sigusr1.watch().listen((s) => print('got $s'));
  Process.killPid(pid, ProcessSignal.sigusr1);
  await Future.delayed(const Duration(milliseconds: 200));
  await sub.cancel();
  print('end');
}
''',
};
