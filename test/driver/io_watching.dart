/// A program that watches files, and what it sees on each system.
library;

/// Changes files in a directory that it watches, and prints the events.
const watchingProgram = r'''
import 'dart:async';
import 'dart:io';

Future<void> pause() => Future.delayed(const Duration(milliseconds: 300));

String told(FileSystemEvent e, String dir) {
  final to = e is FileSystemMoveEvent ? ' ${e.destination?.substring(dir.length)}' : '';
  return '${e.runtimeType} ${e.path.substring(dir.length)} ${e.isDirectory}$to';
}

Future<void> main() async {
  print(FileSystemEntity.isWatchSupported);
  final dir = (Directory('watched')..createSync()).resolveSymbolicLinksSync();
  // FSEvents can tell that it was just made, or not.
  await Future.delayed(const Duration(seconds: 1));
  final events = <String>[];
  final sub = Directory(dir).watch(recursive: true).listen((e) => events.add(told(e, dir)));
  await pause();
  File('$dir/a').writeAsStringSync('1');
  await pause();
  File('$dir/a').renameSync('$dir/b');
  await pause();
  Directory('$dir/d').createSync();
  await pause();
  File('$dir/b').deleteSync();
  await pause();
  await sub.cancel();
  events.forEach(print);
  final f = File('$dir/f')..writeAsStringSync('x');
  final own = <String>[];
  final s2 = f.watch().listen((e) => own.add(told(e, dir)));
  await pause();
  f.writeAsStringSync('y');
  await pause();
  f.deleteSync();
  await pause();
  await s2.cancel();
  own.forEach(print);
  Directory(dir).deleteSync(recursive: true);
}
''';

/// What inotify certainly tells about [watchingProgram], in this order.
const linuxEvents = [
  'true',
  'FileSystemCreateEvent /a false',
  'FileSystemMoveEvent /a false /b',
  'FileSystemCreateEvent /d true',
  'FileSystemDeleteEvent /b false',
  'FileSystemModifyEvent /f false',
  'FileSystemDeleteEvent /f false',
];
