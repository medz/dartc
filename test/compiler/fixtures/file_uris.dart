import 'dart:convert';
import 'dart:io';

void main(List<String> arguments) {
  if (arguments.single == 'base') {
    final before = Uri.base;
    Directory.current = '子目录 #?%';
    final after = Uri.base;
    print(
      jsonEncode([
        before.resolve('子目录%20%23%3F%25/') == after,
        before != after,
        after == Directory.current.uri,
        before.path.endsWith('/'),
        after.path.endsWith('/'),
      ]),
    );
    IOOverrides.runZoned(
      () => print(Uri.base),
      getCurrentDirectory: () => Directory('/虚拟 #?%'),
    );
    final failure = StateError('current directory failed');
    IOOverrides.runZoned(() {
      try {
        print(Uri.base);
        throw StateError('missing failure');
      } on StateError catch (error) {
        print(identical(error, failure));
      }
    }, getCurrentDirectory: () => throw failure);
    return;
  }
  final makeFile = Uri.file;
  final makeDirectory = Uri.directory;
  for (final path in [
    '',
    '/',
    'relative #?%/中文🙂',
    '/a/../b /#?%',
    r'C:\literal\backslashes',
  ]) {
    final file = makeFile(path);
    final directory = makeDirectory(path);
    print(
      jsonEncode([
        file.toString(),
        directory.toString(),
        file.toFilePath(),
        directory.toFilePath(),
        file == makeFile(path, windows: false),
        directory == makeDirectory(path, windows: false),
      ]),
    );
  }
  Platform.isWindows = true;
  print(makeFile(r'C:\still\posix'));
  for (final uri in ['https://example.com/', 'file:///a%2Fb', 'file:///a?b']) {
    try {
      print(Uri.parse(uri).toFilePath());
      throw StateError('invalid file URI accepted');
    } on UnsupportedError {
      print('unsupported');
    }
  }
}
