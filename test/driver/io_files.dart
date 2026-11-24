/// Programs that use files and directories.
const filePrograms = {
  'files at once': r'''
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

void attempt(String name, Object? Function() work) {
  try { print('$name: ${work()}'); } catch (e) { print('$name fails: $e'); }
}

void main() {
  final file = File('a.txt');
  attempt('exists', file.existsSync);
  attempt('read', file.readAsStringSync);
  attempt('length', file.lengthSync);
  attempt('delete', file.deleteSync);
  attempt('modified', file.lastModifiedSync);
  attempt('accessed', file.lastAccessedSync);
  attempt('no directory', () => File('none/a.txt').writeAsStringSync('x'));
  file.writeAsStringSync('hello\nwörld 😀\n');
  attempt('exists', file.existsSync);
  attempt('read', file.readAsStringSync);
  attempt('lines', file.readAsLinesSync);
  attempt('bytes', () => file.readAsBytesSync().runtimeType);
  attempt('length', file.lengthSync);
  file.writeAsStringSync('more', mode: FileMode.append, flush: true);
  attempt('read', file.readAsStringSync);
  file.writeAsBytesSync([104, 105, 0, 255, 300]);
  attempt('bytes', file.readAsBytesSync);
  attempt('bad text', file.readAsStringSync);
  attempt('latin1', () => file.readAsStringSync(encoding: latin1).codeUnits);
  attempt('create', () => (file..createSync()).path);
  attempt('create new', () => file.createSync(exclusive: true));
  attempt('create deep', () => File('d/e/f').createSync());
  File('d/e/f').createSync(recursive: true);
  attempt('deep', File('d/e/f').lengthSync);
  attempt('copy', () => file.copySync('b.txt').path);
  attempt('copied', File('b.txt').readAsBytesSync);
  attempt('copy to none', () => file.copySync('none/b.txt'));
  attempt('copy directory', () => File('d').copySync('x'));
  attempt('rename', () => File('b.txt').renameSync('c.txt').path);
  attempt('old', File('b.txt').existsSync);
  attempt('rename none', () => File('b.txt').renameSync('e.txt'));
  attempt('delete', () { File('c.txt').deleteSync(); return 1; });
  attempt('delete directory', File('d').deleteSync);
  attempt('read directory', File('d').readAsBytesSync);
  attempt('open directory', () => File('d').openSync(mode: FileMode.write));
  attempt('null in path', () => File('a\x00b').existsSync());
  final time = DateTime.utc(2001, 2, 3, 4, 5, 6);
  file.setLastModifiedSync(time);
  file.setLastAccessedSync(time.add(const Duration(hours: 1)));
  attempt('modified', () => file.lastModifiedSync().toUtc());
  attempt('accessed', () => file.lastAccessedSync().toUtc());
  attempt('raw', () => File.fromRawPath(Uint8List.fromList([97, 46, 116, 120, 116])).existsSync());
  attempt('uri', () => File.fromUri(Uri.parse('a.txt')).lengthSync());
  attempt('absolute', () => file.absolute.path.endsWith('/place/a.txt'));
  attempt('parent', () => file.parent.path);
  attempt('toString', () => '$file ${Directory('x')} ${Link('y')}');
  attempt('empty', () => File('').existsSync());
  attempt('zero', () { File('z').createSync(); return File('z').readAsBytesSync(); });
  attempt('device', () => File('/dev/null').readAsBytesSync());
  attempt('device', () => File('/dev/null').existsSync());
  attempt('device', () => File('/dev/null').lengthSync());
  attempt('device', () => File('/dev/null').lastModifiedSync().runtimeType);
  attempt('device', () => FileStat.statSync('/dev/null').type);
  attempt('long name', () => File('x' * 300).existsSync());
  attempt('long name', () => Directory('x' * 300).existsSync());
  attempt('long name', () => File('x' * 300).createSync());
}
''',
  'open files': r'''
import 'dart:io';
import 'dart:typed_data';

void attempt(String name, Object? Function() work) {
  try { print('$name: ${work()}'); } catch (e) { print('$name fails: $e'); }
}

void main() {
  final file = File('a');
  var open = file.openSync(mode: FileMode.write);
  attempt('toString', () => open);
  attempt('path', () => open.path);
  open.writeByteSync(65);
  open.writeByteSync(321);
  open.writeFromSync([66, 67, 68, 1000, -1], 1);
  open.writeFromSync(Uint8List.fromList([9, 8, 7, 6]), 1, 3);
  open.writeFromSync(Int16List.fromList([300, 2]));
  open.writeFromSync(List.generate(5, (i) => i));
  open.writeStringSync('é!');
  attempt('position', open.positionSync);
  attempt('length', open.lengthSync);
  attempt('read', () => open.readSync(4));
  open.setPositionSync(2);
  attempt('read', () => open.readSync(4));
  attempt('read byte', open.readByteSync);
  final buffer = List.filled(6, -1);
  attempt('into', () => '${open.readIntoSync(buffer, 1, 4)} $buffer');
  final bytes = Uint8List(40);
  attempt('into', () => '${open.readIntoSync(bytes, 3)} $bytes');
  attempt('into', () => open.readIntoSync(bytes, 3, 3));
  attempt('at end', () => '${open.readByteSync()} ${open.readSync(3)}');
  open.truncateSync(5);
  attempt('length', open.lengthSync);
  open.setPositionSync(9);
  open.writeByteSync(1);
  open.flushSync();
  attempt('bytes', file.readAsBytesSync);
  attempt('negative', () => open.readSync(-1));
  attempt('range', () => open.readIntoSync(bytes, 9, 5));
  attempt('range', () => open.writeFromSync(bytes, 0, 100));
  attempt('back', () => open.setPositionSync(-5));
  attempt('lock', () { open.lockSync(); open.unlockSync(); return 1; });
  attempt('lock', () { open.lockSync(FileLock.blockingShared, 1, 3); open.unlockSync(1, 3); return 1; });
  open.closeSync();
  attempt('closed', () => open.readByteSync());
  attempt('closed', () => open.closeSync());
  open = file.openSync();
  attempt('read only', () => open.writeByteSync(1));
  attempt('read', () => open.readSync(100));
  open.closeSync();
  open = file.openSync(mode: FileMode.append);
  attempt('appending', open.positionSync);
  open.writeByteSync(77);
  open.setPositionSync(0);
  attempt('appending', () => open.readSync(100));
  open.closeSync();
  open = file.openSync(mode: FileMode.writeOnly);
  attempt('write only', () => open.readByteSync());
  open.closeSync();
  open = file.openSync(mode: FileMode.writeOnlyAppend);
  open.writeByteSync(3);
  open.closeSync();
  attempt('bytes', file.readAsBytesSync);
}
''',
  'directories at once': r'''
import 'dart:io';

void attempt(String name, Object? Function() work) {
  try { print('$name: ${work()}'); } catch (e) { print('$name fails: $e'); }
}

List<String> names(List<FileSystemEntity> list) =>
    [for (final e in list) '${e.runtimeType} ${e.path}']..sort();

void main() {
  final d = Directory('d');
  attempt('exists', d.existsSync);
  attempt('list', d.listSync);
  attempt('delete', d.deleteSync);
  attempt('create', () => (d..createSync()).path);
  attempt('again', () => (d..createSync()).path);
  attempt('deep', () => Directory('x/y').createSync());
  Directory('x/y/z').createSync(recursive: true);
  File('x/f').writeAsStringSync('1');
  File('x/y/g').writeAsStringSync('2');
  File('x/y/.hidden').writeAsStringSync('2');
  Link('x/l').createSync('f');
  Link('x/m').createSync('y');
  Link('x/n').createSync('none');
  Link('x/y/back').createSync('../../x');
  attempt('list', () => names(Directory('x').listSync()));
  attempt('links', () => names(Directory('x').listSync(followLinks: false)));
  attempt('all', () => names(Directory('x').listSync(recursive: true)));
  attempt('all links', () => names(Directory('x').listSync(recursive: true, followLinks: false)));
  attempt('slash', () => names(Directory('x/').listSync()));
  attempt('file as directory', () => Directory('x/f').listSync());
  attempt('create at file', () => Directory('x/f').createSync());
  attempt('below file', () => Directory('x/f/g').createSync());
  attempt('exists', Directory('x/f').existsSync);
  attempt('delete full', Directory('x').deleteSync);
  attempt('rename', () => Directory('x').renameSync('w').path);
  attempt('rename file', () => Directory('w/f').renameSync('v').path);
  attempt('rename none', () => Directory('x').renameSync('v').path);
  attempt('rename over', () => Directory('d').renameSync('w').path);
  attempt('resolve', () => Link('w/m').resolveSymbolicLinksSync().endsWith('/place/w/y'));
  attempt('resolve none', () => Link('w/n').resolveSymbolicLinksSync());
  attempt('target', () => Link('w/m').targetSync());
  attempt('no target', () => Link('w/f').targetSync());
  attempt('link', () => Link('w/m').createSync('k'));
  attempt('update', () { Link('w/m').updateSync('g'); return Link('w/m').targetSync(); });
  attempt('rename link', () => Link('w/m').renameSync('w/o').targetSync());
  attempt('rename no link', () => Link('w/f').renameSync('w/p'));
  attempt('delete link', () { Link('w/o').deleteSync(); return Link('w/o').existsSync(); });
  attempt('delete no link', () => Link('w/f').deleteSync());
  attempt('link exists', () => '${Link('w/n').existsSync()} ${File('w/n').existsSync()} ${Link('w/f').existsSync()}');
  for (final path in ['w', 'w/f', 'w/l', 'w/n', 'none', '/dev/null']) {
    attempt('type', () => '${FileSystemEntity.typeSync(path)} ${FileSystemEntity.typeSync(path, followLinks: false)}');
    attempt('is', () => '${FileSystemEntity.isFileSync(path)} ${FileSystemEntity.isDirectorySync(path)} ${FileSystemEntity.isLinkSync(path)}');
  }
  attempt('identical', () => FileSystemEntity.identicalSync('w/f', 'w/l'));
  attempt('identical', () => FileSystemEntity.identicalSync('w/f', 'w/../w/f'));
  attempt('identical', () => FileSystemEntity.identicalSync('w/f', 'none'));
  final stat = File('w/f').statSync();
  attempt('stat', () => '${stat.type} ${stat.size} ${stat.modeString()} ${stat.mode}');
  attempt('stat', () => '${File('none').statSync().type} ${FileStat.statSync('none').size}');
  attempt('stat', () => '${FileStat.statSync('w').type} ${FileStat.statSync('w/l').type}');
  attempt('times', () => stat.modified.difference(DateTime.now()).inMinutes);
  attempt('stat', () => File('w/f').lastModifiedSync() .difference(stat.modified).inSeconds);
  final current = Directory.current.path;
  attempt('current', () => current.endsWith('/place'));
  Directory.current = 'w';
  attempt('current', () => Directory.current.path == '$current/w');
  attempt('base', () => Uri.base.path == '$current/w/');
  attempt('here', () => File('f').existsSync());
  attempt('no current', () => Directory.current = 'none');
  Directory.current = current;
  final temp = Directory.systemTemp.createTempSync('abc');
  attempt('temp', () => '${temp.existsSync()} ${temp.path.split('/').last.length} ${temp.path.split('/').last.startsWith('abc')}');
  temp.deleteSync();
  attempt('temp', () => Directory('none').createTempSync('abc').path.length);
  attempt('temp', () => d.createTempSync().path.length);
  attempt('delete', () { Directory('w').deleteSync(recursive: true); return Directory('w').existsSync(); });
  attempt('delete', () { Directory('d').deleteSync(recursive: true); return d.existsSync(); });
  File('e').createSync();
  attempt('delete file', () { File('e').deleteSync(recursive: true); return File('e').existsSync(); });
  attempt('delete none', () => Directory('w').deleteSync(recursive: true));
}
''',
  'files later': r'''
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

Future<void> attempt(String name, Future<Object?> Function() work) async {
  try { print('$name: ${await work()}'); } catch (e) { print('$name fails: $e'); }
}

Future<void> main() async {
  final file = File('a');
  await attempt('exists', file.exists);
  await attempt('read', file.readAsString);
  await attempt('length', file.length);
  await attempt('modified', file.lastModified);
  await attempt('delete', file.delete);
  await attempt('create deep', () => File('d/e/f').create());
  await attempt('create deep', () => File('d/e/f').create(recursive: true));
  await attempt('create new', () => File('d/e/f').create(exclusive: true));
  await attempt('write', () => file.writeAsString('één\ntwee\n', flush: true));
  await attempt('append', () => file.writeAsBytes([1, 2, 300], mode: FileMode.append));
  await attempt('read', file.readAsString);
  await attempt('lines', file.readAsLines);
  await attempt('bytes', file.readAsBytes);
  await attempt('bad', () => file.readAsString(encoding: ascii));
  await attempt('copy', () => file.copy('b'));
  await attempt('rename', () => File('b').rename('c'));
  await attempt('length', File('c').length);
  await attempt('set', () => file.setLastModified(DateTime.utc(2010)));
  await attempt('set', () => file.setLastAccessed(DateTime.utc(2011)));
  await attempt('modified', () async => (await file.lastModified()).toUtc());
  await attempt('accessed', () async => (await file.lastAccessed()).toUtc());
  await attempt('stat', () async => (await file.stat()).size);
  await attempt('stat', () async => (await File('x').stat()).type);
  await attempt('type', () => FileSystemEntity.type('d'));
  await attempt('identical', () => FileSystemEntity.identical('a', 'c'));
  await attempt('identical', () => FileSystemEntity.identical('a', 'x'));
  await attempt('resolve', () async => (await file.resolveSymbolicLinks()).endsWith('/a'));
  await attempt('link', () async => (await Link('l').create('a')).path);
  await attempt('link', () => Link('l').create('a'));
  await attempt('target', Link('l').target);
  await attempt('target', Link('a').target);
  await attempt('update', () async => (await Link('l').update('c')).path);
  await attempt('rename link', () async => (await Link('l').rename('m')).target());
  await attempt('delete link', () => Link('m').delete());
  await attempt('delete link', () => Link('a').delete());
  await attempt('open', () => File('d').open());
  final open = await file.open(mode: FileMode.append);
  await attempt('position', open.position);
  await attempt('write', () => open.writeFrom([7, 8, 9], 1));
  await attempt('write', () => open.writeFrom(Uint8List.sublistView(Uint8List(9), 2, 4)));
  await attempt('write', () => open.writeByte(333));
  await attempt('write', () => open.writeString('é'));
  await attempt('flush', open.flush);
  await attempt('length', open.length);
  await attempt('set', () => open.setPosition(3));
  await attempt('set', () => open.setPosition(-3));
  await attempt('byte', open.readByte);
  await attempt('read', () => open.read(5));
  final into = List.filled(5, 0);
  await attempt('into', () async => '${await open.readInto(into, 1, 4)} $into');
  await attempt('lock', () => open.lock(FileLock.shared));
  await attempt('unlock', open.unlock);
  await attempt('truncate', () => open.truncate(4));
  await attempt('read', () => open.read(5));
  await attempt('byte', open.readByte);
  final pending = open.length();
  await attempt('pending', open.length);
  try { open.lengthSync(); } catch (e) { print(e); }
  print(await pending);
  await attempt('close', open.close);
  await attempt('closed', open.length);
  await attempt('delete', file.delete);
  await attempt('gone', file.exists);
  await attempt('all', () async => (await Future.wait([for (var i = 0; i < 20; i++) File('f$i').writeAsString('$i')])).length);
  await attempt('all', () => Future.wait([for (var i = 0; i < 20; i++) File('f$i').readAsString()]));
  runZonedCheck();
}

void runZonedCheck() {
  File('none').readAsString().catchError((Object e) { print('caught $e'); return ''; });
  File('f0').readAsString().then(print);
}
''',
  'streams of files': r'''
import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> attempt(String name, Future<Object?> Function() work) async {
  try { print('$name: ${await work()}'); } catch (e) { print('$name fails: $e'); }
}

Future<void> main() async {
  final file = File('a');
  final sink = file.openWrite();
  sink.write('hello ');
  sink.writeln(42);
  sink.writeAll([1, 2, 3], ',');
  sink.writeCharCode(0xe9);
  sink.add([10, 11]);
  await sink.addStream(Stream.fromIterable([[65, 66], [67]]));
  await sink.flush();
  print(file.lengthSync());
  sink.write('end');
  await attempt('close', () async { await sink.close(); return file.length(); });
  await attempt('all', () => file.openRead().toList());
  await attempt('part', () => file.openRead(3, 6).toList());
  await attempt('from', () => file.openRead(20).toList());
  await attempt('none', () => file.openRead(6, 6).toList());
  await attempt('beyond', () => file.openRead(100).toList());
  await attempt('negative', () => file.openRead(-1).toList());
  await attempt('wrong', () => file.openRead(5, 3).toList());
  await attempt('missing', () => File('x').openRead().toList());
  await attempt('missing', () async { final s = File('x/y').openWrite(); s.write('a'); await s.close(); return 1; });
  await attempt('lines', () => file.openRead().transform(latin1.decoder).transform(const LineSplitter()).toList());
  const lots = 60000;
  final big = File('big');
  final out = big.openWrite();
  for (var i = 0; i < lots; i++) out.write('line $i\n');
  await out.close();
  print(big.lengthSync());
  var blocks = 0, bytes = 0;
  await for (final block in big.openRead()) { blocks++; bytes += block.length; }
  print('$blocks $bytes');
  print(await big.openRead().transform(utf8.decoder).transform(const LineSplitter()).length);
  print(await big.openRead().transform(utf8.decoder).transform(const LineSplitter()).skip(lots - 2).first);
  await for (final block in big.openRead()) { print(block.length); break; }
  late StreamSubscription<List<int>> subscription;
  var seen = 0;
  final done = Completer<void>();
  subscription = big.openRead().listen((block) {
    seen += block.length;
    subscription.pause(Future.delayed(const Duration(milliseconds: 1)));
  }, onDone: done.complete);
  await done.future;
  print(seen);
  await big.openRead().pipe(File('copy').openWrite());
  print(File('copy').lengthSync());
  final app = file.openWrite(mode: FileMode.append);
  app.write('!');
  await app.close();
  print(file.lengthSync());
  final pipe = await Pipe.create();
  final received = pipe.read.transform(utf8.decoder).join();
  pipe.write.write('x' * (lots * 3));
  pipe.write.write('through');
  await pipe.write.close();
  final text = await received;
  print('${text.length} ${text.substring(lots * 3 - 2)}');
  final two = Pipe.createSync();
  var ticks = 0;
  final timer = Timer.periodic(const Duration(milliseconds: 5), (_) {
    if (++ticks == 4) { two.write.write('late'); two.write.close(); }
  });
  print(await two.read.transform(utf8.decoder).join());
  timer.cancel();
  print(ticks > 3);
}
''',
  'directories later': r'''
import 'dart:async';
import 'dart:io';

Future<void> attempt(String name, Future<Object?> Function() work) async {
  try { print('$name: ${await work()}'); } catch (e) { print('$name fails: $e'); }
}

Future<List<String>> names(Stream<FileSystemEntity> list) async =>
    [await for (final e in list) '${e.runtimeType} ${e.path}']..sort();

Future<void> main() async {
  const lots = 60000;
  final d = Directory('d');
  await attempt('exists', d.exists);
  await attempt('list', d.list().toList);
  await attempt('create', d.create);
  await attempt('create', () => Directory('d/x/y').create());
  await attempt('create', () => Directory('d/x/y').create(recursive: true));
  for (var i = 0; i < lots ~/ 100; i++) File('d/f$i').createSync();
  File('d/x/g').createSync();
  Link('d/l').createSync('x');
  Link('d/x/back').createSync('../x');
  Link('d/x/none').createSync('none');
  await attempt('list', () => names(d.list()));
  await attempt('all', () => names(d.list(recursive: true)));
  await attempt('links', () => names(d.list(recursive: true, followLinks: false)));
  await attempt('first', () async => (await d.list().first).path.length);
  await attempt('file', () => File('d/f1').parent.list().length);
  await attempt('not a directory', () => Directory('d/f1').list().length);
  var count = 0;
  late StreamSubscription<FileSystemEntity> s;
  final done = Completer<void>();
  s = d.list().listen((e) {
    if (++count % 20 == 0) { s.pause(); Timer(const Duration(milliseconds: 1), s.resume); }
  }, onDone: done.complete);
  await done.future;
  print(count);
  await attempt('rename', () async => (await d.rename('e')).path);
  await attempt('rename', () => d.rename('f'));
  await attempt('temp', () async { final t = await Directory('e').createTemp('a'); return t.path.length; });
  await attempt('temp', () => Directory('no').createTemp('a'));
  await attempt('delete', () => Directory('e').delete());
  await attempt('delete', () => Directory('e').delete(recursive: true));
  await attempt('delete', () => Directory('e').delete(recursive: true));
  Directory('p').createSync();
  Directory('p/q').createSync();
  Directory('p/r').createSync();
  Directory('p').list().listen((e) => print(e.path.length), onDone: () => print('end'));
}
''',
  'callbacks, files and timers': r'''
import 'dart:async';
import 'dart:ffi';
import 'dart:io';

Future<void> main() async {
  final calls = <int>[], all = Completer<void>();
  final callable = NativeCallable<Void Function(Int32)>.listener((int x) {
    calls.add(x);
    if (calls.length == 20) all.complete();
  });
  final call = callable.nativeFunction.asFunction<void Function(int)>();
  var ticks = 0;
  final timer = Timer.periodic(const Duration(milliseconds: 2), (_) => ticks++);
  final texts = <String>[];
  for (var i = 0; i < 20; i++) {
    call(i);
    await File('f$i').writeAsString('$i');
    texts.add(await File('f$i').readAsString());
  }
  await all.future;
  while (ticks < 5) { await Future.delayed(const Duration(milliseconds: 1)); }
  print(calls);
  print(texts);
  timer.cancel();
  Timer(const Duration(milliseconds: 20), () { call(99); });
  Timer.periodic(const Duration(milliseconds: 5), (timer) {
    if (calls.last != 99) return;
    print(calls.last); callable.close(); timer.cancel();
  });
}
''',
};
