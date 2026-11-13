import 'dart:convert';
import 'dart:io';

import 'package:dartc/sdk.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late SourceDirectory sources;
  setUp(() {
    directory = (Directory(
      'build/test/sdk',
    )..createSync(recursive: true)).createTempSync('directory-');
    addTearDown(() => directory.deleteSync(recursive: true));
    for (final name in ['std', 'runtime', 'patches']) {
      Directory('${directory.path}/sdk/$name').createSync(recursive: true);
    }
    for (final path in [
      'lib/runtime/contracts.dart',
      'lib/layout/memory.dart',
      'lib/src/layout/memory_layout.dart',
      'sdk/runtime/allocator.dart',
    ]) {
      final output = File('${directory.path}/$path');
      output.parent.createSync(recursive: true);
      File(path).copySync(output.path);
    }
    sources = SourceDirectory(directory);
  });

  test(
    'reads edits directly and packs a reproducible independent snapshot',
    () {
      const path = 'sdk/runtime/allocator.dart';
      final original = sources.read(path);
      final packed = SourceArchive.encode(sources);
      expect(SourceArchive.encode(sources), packed);
      final archive = SourceArchive(packed);
      expect(archive.paths.toSet(), sources.paths.toSet());
      expect(archive.read(path), original);
      final file = File('${directory.path}/$path');
      file.writeAsStringSync('${utf8.decode(original)}\n// Updated source.\n');
      expect(sources.read(path), file.readAsBytesSync());
      expect(sources.length(path), file.lengthSync());
      expect(archive.read(path), original);
      expect(SourceArchive.encode(sources), isNot(packed));
      expect(() => sources.read(path)[0] = 0, throwsUnsupportedError);
      final added = File('${directory.path}/sdk/runtime/added.dart')
        ..writeAsStringSync('int value() => 1;');
      expect(sources.paths, contains('sdk/runtime/added.dart'));
      expect(sources.read('sdk/runtime/added.dart'), added.readAsBytesSync());
    },
  );

  test('rejects missing files, traversal and symbolic links', () {
    for (final path in [
      'sdk/runtime/missing.dart',
      'sdk/runtime/../../pubspec.yaml',
      '/sdk/runtime/allocator.dart',
      'sdk/runtime/./allocator.dart',
      'sdk\\runtime\\allocator.dart',
      'sdk/runtime/allocator.dart\u0000',
      'lib/compiler.dart',
    ]) {
      expect(sources.contains(path), isFalse);
      expect(sources.length(path), isNull);
      expect(() => sources.read(path), throwsFormatException);
    }
    final target = File('${directory.path}/outside.dart')
      ..writeAsStringSync('outside');
    final link = Link('${directory.path}/sdk/runtime/link.dart')
      ..createSync(target.absolute.path);
    expect(() => sources.read('sdk/runtime/link.dart'), throwsFormatException);
    expect(() => SourceArchive.encode(sources), throwsFormatException);
    link.deleteSync();
    Directory('${directory.path}/sdk/runtime').deleteSync(recursive: true);
    Link('${directory.path}/sdk/runtime').createSync(directory.absolute.path);
    expect(
      () => sources.read('sdk/runtime/outside.dart'),
      throwsFormatException,
    );
    expect(() => SourceArchive.encode(sources), throwsFormatException);
  });
}
