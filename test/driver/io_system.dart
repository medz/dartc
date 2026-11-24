/// Programs that write, or use the environment.
const systemPrograms = {
  'output': r'''
import 'dart:convert';
import 'dart:io';

void attempt(String name, Object? Function() work) {
  try { print('$name: ${work()}'); } catch (e) { print('$name fails: $e'); }
}

Future<void> main() async {
  stdout.write('a');
  print('b');
  stdout.writeln('cé');
  stdout.writeAll([1, 'x', null], '-');
  stdout.writeCharCode(10);
  stdout.add([104, 105, 10]);
  stderr.write('error ');
  stderr.writeln(5);
  await stdout.addStream(Stream.fromIterable([[65, 10], utf8.encode('é\n')]));
  await stdout.flush();
  stdout.encoding = latin1;
  stdout.write('ab\n');
  stdout.encoding = utf8;
  stdout.lineTerminator = '\r\n';
  stdout.write('one\ntwo\n');
  stdout.writeln('three');
  stdout.lineTerminator = '\n';
  attempt('terminal', () => stdout.hasTerminal);
  attempt('columns', () => stdout.terminalColumns);
  attempt('lines', () => stdout.terminalLines);
  attempt('escapes', () => stdout.supportsAnsiEscapes);
  attempt('escapes', () => stderr.supportsAnsiEscapes);
  attempt('type', () => stdioType(stdout));
  attempt('type', () => stdioType(stderr));
  attempt('type', () => stdioType(stdin));
  attempt('input', () => stdin.hasTerminal);
  attempt('echo', () => stdin.echoMode);
  attempt('echo', () => stdin.echoMode = false);
  attempt('newline', () => stdin.echoNewlineMode);
  attempt('newline', () => stdin.echoNewlineMode = false);
  attempt('line', () => stdin.lineMode);
  attempt('line', () => stdin.lineMode = false);
  attempt('input escapes', () => stdin.supportsAnsiEscapes);
  final sink = stdout.nonBlocking;
  sink.write('not blocking\n');
  await sink.flush();
  const lots = 60000;
  stdout.write('x' * lots);
  stdout.writeln();
  final done = stdout.done;
  await stderr.close();
  await stdout.close();
  await done;
  print('lost');
  try { stdout.write('lost'); } catch (e) { print(e); }
}
''',
  'exit at once': r'''
import 'dart:async';
import 'dart:io';
void main() {
  stdout.write('before ');
  exitCode = 3;
  Timer.run(() { print('timer'); exit(300); });
  Timer(const Duration(seconds: 100), () => print('never'));
}
''',
  'exit code of an error': r'''
import 'dart:io';
void main() {
  print('start');
  exitCode = 3;
  throw 'failed';
}
''',
  'exit code set later': r'''
import 'dart:io';
Future<void> main() async {
  print('start');
  await File('a').writeAsString('x');
  exitCode = -2;
}
''',
  'overrides': r'''
import 'dart:io';

base class Own extends IOOverrides {
  File createFile(String path) => super.createFile('$path.own');
  Directory getCurrentDirectory() => Directory('/somewhere');
  FileSystemEntityType fseGetTypeSync(String path, bool followLinks) => FileSystemEntityType.link;
  Never exit(int code) => throw 'exit $code';
}

void main() {
  IOOverrides.runWithIOOverrides(() {
    print(File('a').path);
    print(Directory.current.path);
    print(Uri.base);
    print(Link('a').absolute.path);
    print(FileSystemEntity.isLinkSync('a'));
    try { exit(3); } catch (e) { print(e); }
  }, Own());
  IOOverrides.runZoned(() {
    try { print(FileStat.statSync('/').size); } catch (e) { print(e); }
    try { stdout.write('x'); } catch (e) { print(e); }
  }, statSync: (path) => throw 'no $path', stdout: () => throw 'no output');
  print(Uri.base.path.endsWith('/place/'));
}
''',
};

/// What systems agree on.
const environmentProgram = r'''
import 'dart:io';

Future<void> main(List<String> arguments) async {
  print(Platform.environment['DARTC_TEST']);
  print(Platform.environment['DARTC_NONE']);
  print(Platform.environment.containsKey('PATH'));
  try { Platform.environment['x'] = 'y'; } catch (e) { print(e); }
  print(Platform.numberOfProcessors > 0);
  print(Platform.pathSeparator);
  print(Platform.lineTerminator.length);
  print(Platform.packageConfig);
  print(Platform.executableArguments);
  print(Platform.version.split(' ').first);
  print(Platform.executable.isEmpty);
  print(File(Platform.resolvedExecutable).existsSync());
  print(File.fromUri(Platform.script).existsSync());
  print(pid > 1);
  final watch = Stopwatch()..start();
  sleep(const Duration(milliseconds: 30));
  print(watch.elapsedMilliseconds >= 30);
  try { sleep(const Duration(milliseconds: -1)); } catch (e) { print(e); }
  print(systemEncoding.name);
  print(systemEncoding.decode(systemEncoding.encode('é')));
  print(exitCode);
  exitCode = 7;
  print(exitCode);
}
''';

const platformProgram = r'''
import 'dart:io';
void main() {
  print(Platform.operatingSystem);
  print(Platform.operatingSystemVersion);
  print('${Platform.isMacOS} ${Platform.isLinux} ${Platform.isWindows} ${Platform.isAndroid} ${Platform.isIOS} ${Platform.isFuchsia}');
  print(Platform.localHostname);
  print(Platform.localeName);
  print(Platform.version.split(' ').last);
}
''';

/// Programs that read what they are given.
final inputPrograms = {
  'lines at once': (
    r'''
import 'dart:convert';
import 'dart:io';
void main() {
  print(stdin.readLineSync());
  print(stdin.readLineSync(retainNewlines: true)!.codeUnits);
  print(stdin.readByteSync());
  print(stdin.readLineSync(encoding: latin1)!.codeUnits);
  var line = stdin.readLineSync();
  while (line != null) {
    print('<$line>');
    line = stdin.readLineSync();
  }
  print(stdin.readByteSync());
  print(stdin.readLineSync());
}
''',
    'first\nsecond\nthird é\n\nünd 😀\nlast',
  ),
  'no input': (
    r'''
import 'dart:io';
Future<void> main() async {
  print(stdin.readLineSync());
  print(stdin.readByteSync());
  print(await stdin.toList());
}
''',
    '',
  ),
  'lines as they come': (
    r'''
import 'dart:convert';
import 'dart:io';
Future<void> main() async {
  await for (final line in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    print('<$line>');
  }
  print('end');
  try { stdin.listen(print); } catch (e) { print(e); }
  try { print(stdin.readByteSync()); } catch (e) { print(e); }
  print(stdin.hasTerminal);
}
''',
    'one\ntwo é\n\nlast',
  ),
  'the first line only': (
    r'''
import 'dart:convert';
import 'dart:io';
Future<void> main() async {
  print(await stdin.transform(utf8.decoder).transform(const LineSplitter()).first);
  print('end');
  try { print(stdin.readLineSync()); } catch (e) { print(e); }
}
''',
    'one\ntwo\n',
  ),
  'some lines, then the rest': (
    r'''
import 'dart:io';
Future<void> main() async {
  print(stdin.readLineSync());
  final bytes = await stdin.expand((bytes) => bytes).toList();
  print(String.fromCharCodes(bytes));
}
''',
    'one\ntwo\nthree\n',
  ),
  'much input': (
    r'''
import 'dart:async';
import 'dart:convert';
import 'dart:io';
Future<void> main() async {
  var lines = 0, sum = 0;
  late StreamSubscription<String> s;
  s = stdin.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
    lines++;
    sum += int.parse(line);
    if (lines % 100 == 0) { s.pause(); Timer(const Duration(milliseconds: 1), s.resume); }
  }, onDone: () => print('$lines $sum'));
}
''',
    _numbers,
  ),
  'copied input': (
    r'''
import 'dart:io';
Future<void> main() => stdin.pipe(stdout);
''',
    'some\ninput\n',
  ),
  'input into a file': (
    r'''
import 'dart:io';
Future<void> main() async {
  await stdin.pipe(File('copy').openWrite());
  print(File('copy').readAsStringSync());
}
''',
    'some\ninput\n',
  ),
};

final _numbers = [for (var i = 0; i < 30000; i++) '$i\n'].join();
