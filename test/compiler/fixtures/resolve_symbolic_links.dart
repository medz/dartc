import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  switch (args.single) {
    case 'paths':
      final resolved = <String>[];
      for (final factory in <FileSystemEntity Function(String)>[
        File.new,
        Directory.new,
        Link.new,
      ]) {
        for (final path in [
          '.',
          'real/./inner/..',
          'file-link',
          'chain',
          'dir-link/../sibling.txt',
          'real/中文.txt',
          'file-link\u0000ignored',
          '${Directory.current.path}/real/中文.txt',
        ]) {
          final resolve = factory(path).resolveSymbolicLinksSync;
          resolved.add(resolve());
        }
      }
      var pressure = 0;
      for (var i = 0; i < 40000; i++) {
        pressure += <Object>[i, '$i'].length;
      }
      if (pressure != 80000) throw StateError('allocation pressure');
      print(jsonEncode(resolved));
    case 'failures':
      final failures = <List<Object?>>[];
      for (final path in [
        '',
        'missing',
        'dangling',
        'loop',
        'real/中文.txt/child',
        'x' * 300,
      ]) {
        try {
          File(path).resolveSymbolicLinksSync();
          throw StateError('unexpected resolution');
        } on FileSystemException catch (error) {
          failures.add([
            error.path,
            error.osError!.errorCode,
            error.osError!.message.isNotEmpty,
            error is PathNotFoundException,
          ]);
        }
      }
      print(jsonEncode(failures));
    default:
      throw ArgumentError(args);
  }
}
