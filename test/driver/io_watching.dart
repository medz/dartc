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

/// Dart 3.14.0 on macOS drops the first byte after the root slash.
const rootWatchingProgram = r'''
import 'dart:async';
import 'dart:io';

Future<void> main() async {
  final name = 'watch-root-$pid';
  final directory = Directory.current.resolveSymbolicLinksSync();
  final file = File('$directory/$name');
  final change = Directory('/')
      .watch(events: FileSystemEvent.create, recursive: true)
      .firstWhere((event) => event.path.endsWith('/$name'));
  await Future<void>.delayed(const Duration(milliseconds: 250));
  file.writeAsStringSync('watch');
  print((await change).path == file.path);
}
''';

/// A failed first watch reports the error and lets the program exit.
const failedWatchingProgram = r'''
import 'dart:io';

Future<void> main() async {
  try {
    await Directory('missing').watch().first;
  } on FileSystemException catch (error) {
    print(error.osError?.errorCode == 2);
  }
}
''';

/// Watches of one directory receive their own events in either order.
const sharedWatchingProgram = r'''
import 'dart:io';

Future<void> check(int first, int second) async {
  final directory = Directory('watched')..createSync();
  final file = File('watched/file');
  Future<List<int>> typesUntilWrite(int mask) async {
    final seen = <int>[];
    await for (final event in directory.watch(events: mask)) {
      if (event.path != file.path) continue;
      seen.add(event.type);
      if (event is FileSystemModifyEvent && event.contentChanged) break;
    }
    return seen;
  }

  final seen = Future.wait([typesUntilWrite(first), typesUntilWrite(second)]);
  try {
    await Directory('missing').watch().first;
  } on FileSystemException {
    file.writeAsStringSync('watch');
  }
  final [left, right] = await seen;
  final (all, modify) = first == FileSystemEvent.all ? (left, right) : (right, left);
  print('${all.contains(FileSystemEvent.create)} '
      '${modify.every((type) => type == FileSystemEvent.modify)}');
  directory.deleteSync(recursive: true);
}

Future<void> main() async {
  await check(FileSystemEvent.all, FileSystemEvent.modify);
  await check(FileSystemEvent.modify, FileSystemEvent.all);
}
''';
