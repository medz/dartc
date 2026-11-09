import 'dart:io';

import 'package:dartc/src/compiler/permissions.dart';
import 'package:test/test.dart';

void main() {
  test(
    'executable permissions preserve read/write bits and report OS errors',
    () {
      final directory = (Directory(
        'build/test',
      )..createSync(recursive: true)).createTempSync('permissions-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File.fromUri(directory.uri.resolve('program'))
        ..writeAsStringSync('unchanged');
      final before = file.statSync().mode & 0x1ff;
      makeExecutable(file);
      expect(file.statSync().mode & 0x1ff, before | (before & 0x124) >> 2);
      expect(file.readAsStringSync(), 'unchanged');
      final missing = File.fromUri(directory.uri.resolve('missing'));
      expect(
        () => makeExecutable(missing),
        throwsA(
          isA<FileSystemException>().having(
            (e) => e.osError?.errorCode,
            'errno',
            2,
          ),
        ),
      );
      expect(missing.existsSync(), isFalse);
    },
  );
}
