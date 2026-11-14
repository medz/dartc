import 'dart:io';

import 'package:dartc/sdk.dart';
import 'package:dartc/src/sdk/unicode_case_data.dart';
import 'package:test/test.dart';

void main() {
  test(
    'pinned case data compiles and survives independent source packaging',
    () async {
      final directory = (Directory(
        'build/test/sdk',
      )..createSync(recursive: true)).createTempSync('unicode-');
      addTearDown(() => directory.deleteSync(recursive: true));
      for (final name in ['sdk/std', 'sdk/runtime', 'sdk/patches']) {
        Directory('${directory.path}/$name').createSync(recursive: true);
      }
      for (final path in [
        'lib/runtime/contracts.dart',
        'lib/layout/memory.dart',
        'lib/src/layout/memory_layout.dart',
        'sdk/patches/unicode_case.dart',
        ...unicodeCaseInputs.keys,
      ]) {
        final output = File('${directory.path}/$path');
        output.parent.createSync(recursive: true);
        File(path).copySync(output.path);
      }
      final sources = SourceDirectory(directory);
      expect(sources.paths, contains(unicodeCaseSource));
      final data = sources.read(unicodeCaseSource);
      expect(sources.length(unicodeCaseSource), data.length);
      expect(() => data[0] = 0, throwsUnsupportedError);
      final archive = SourceArchive(SourceArchive.encode(sources));
      expect(archive.read(unicodeCaseSource), data);
      expect(archive.paths.toSet(), sources.paths.toSet());
      expect(
        archive.fingerprint('sdk/patches/'),
        sources.fingerprint('sdk/patches/'),
      );
      for (final path in unicodeCaseInputs.keys) {
        final input = File('${directory.path}/$path');
        final original = input.readAsBytesSync();
        for (final provider in [sources, archive]) {
          if (path.endsWith('/LICENSE')) {
            expect(provider.read(path), original);
          } else {
            expect(provider.contains(path), isFalse);
            expect(provider.length(path), isNull);
            expect(() => provider.read(path), throwsFormatException);
          }
        }
        input.writeAsStringSync('\n', mode: FileMode.append);
        expect(() => sources.read(unicodeCaseSource), throwsFormatException);
        expect(() => SourceArchive.encode(sources), throwsFormatException);
        input.deleteSync();
        expect(sources.contains(unicodeCaseSource), isFalse);
        expect(sources.length(unicodeCaseSource), isNull);
        expect(() => sources.read(unicodeCaseSource), throwsFormatException);
        expect(() => SourceArchive.encode(sources), throwsFormatException);
        expect(archive.read(unicodeCaseSource), data);
        input.writeAsBytesSync(original);
      }
      for (final path in unicodeCaseInputs.keys.where(
        (path) => path.endsWith('.txt'),
      )) {
        File('${directory.path}/$path').deleteSync();
      }
      final generated = File('${directory.path}/unicode_case_data.dart')
        ..writeAsBytesSync(archive.read(unicodeCaseSource));
      File('${directory.path}/unicode_case.dart')
          .writeAsBytesSync(archive.read('sdk/patches/unicode_case.dart'));
      final entry = File('${directory.path}/check.dart')
        ..writeAsStringSync(r"""
import 'unicode_case_data.dart';
import 'unicode_case.dart' as leaf;
void main() {
  assert(leaf.convertCase('stra\u00dfe', upper: true) == 'STRASSE');
  assert(leaf.convertCase('A\u03a3\u0345', upper: false) == 'a\u03c2\u0345');
  assert(leaf.convertCase('\u0345\u03a3', upper: false) == '\u0345\u03c3');
  final original = String.fromCharCodes([0x61, 0xd800]);
  assert(identical(leaf.convertCase(original, upper: false), original));
  assert(lower[0x130] == 'i\u0307');
  assert(upper[0xdf] == 'SS');
  assert(upper[0xfb03] == 'FFI');
  assert(lower[0x1e900] == '\u{1e922}');
  assert(cased.contains(0x1e922));
  assert(cased.contains(0x345) && ignored.contains(0x345));
  assert(!ignored.contains(0x31));
  assert(!lower.containsKey(0xd800) && !upper.containsKey(0x10ffff));
}
""");
      final result = await Process.run(Platform.resolvedExecutable, [
        '--enable-asserts',
        entry.path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(archive.read(unicodeCaseSource), generated.readAsBytesSync());
    },
  );
}
