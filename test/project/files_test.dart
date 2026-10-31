import 'dart:io';

import 'package:dartc/project.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('dartc-project-test-');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test(
    'reads UTF-8 without losing BOM, line endings or replacement characters',
    () async {
      final file = File.fromUri(directory.uri.resolve('source.dart'));
      await file.writeAsBytes([0xef, 0xbb, 0xbf, 47, 47, 32, 0xff, 13, 10, 10]);
      expect(await readFileSource(file.uri), '\ufeff// \ufffd\r\n\n');
      expect(
        await readFileSource(directory.uri.resolve('missing.dart')),
        isNull,
      );
      expect(await readFileSource(Uri.parse('memory:source')), isNull);
      await expectLater(
        readFileSource(directory.uri),
        throwsA(isA<FileSystemException>()),
      );
    },
  );

  test('reports malformed file URIs as format errors', () async {
    for (final uri in [
      directory.uri.resolve('a%2fb.dart'),
      directory.uri.resolve('source.dart?query'),
      directory.uri.resolve('source.dart#fragment'),
    ]) {
      await expectLater(readFileSource(uri), throwsFormatException);
    }
  });

  test(
    'loads real files using package configuration discovered above the entry',
    () async {
      final tool = Directory.fromUri(directory.uri.resolve('.dart_tool/'));
      final lib = Directory.fromUri(directory.uri.resolve('lib/'));
      final bin = Directory.fromUri(directory.uri.resolve('bin/'));
      await tool.create();
      await lib.create();
      await bin.create();
      await File.fromUri(tool.uri.resolve('package_config.json')).writeAsString(
        '{"configVersion":2,"packages":[{"name":"app","rootUri":"../","packageUri":"lib/","languageVersion":"3.13"}]}',
      );
      await File.fromUri(lib.uri.resolve('value.dart'))
          .writeAsString('int value = 1;');
      final entry = File.fromUri(bin.uri.resolve('main.dart'));
      await entry.writeAsString(
        "import 'package:app/value.dart'; void main() {}",
      );
      final packages = await findPackageConfiguration(entry.uri);
      final result = await ProjectLoader(
        packages: packages!,
        readSource: (uri) =>
            uri == Uri.parse('dart:core') ? '' : readFileSource(uri),
      ).load(entry.uri);
      expect(result.diagnostics, isEmpty);
      expect(result.libraries, contains(Uri.parse('package:app/value.dart')));
    },
  );
}
