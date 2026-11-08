import 'dart:io';

import 'package:dartc/artifact.dart';
import 'package:dartc/formats.dart';
import 'package:dartc/linker.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

void main() {
  final target = Target.host();
  final object = _object(target);
  late Directory directory;
  setUp(() {
    directory = (Directory(
      'build/test',
    )..createSync(recursive: true)).createTempSync('linker-');
  });
  tearDown(() => directory.deleteSync(recursive: true));

  test('all targets link deterministically', () async {
    for (final os in OperatingSystem.values) {
      for (final arch in Architecture.values) {
        final target = Target(os, arch);
        final object = _object(target);
        for (final kind in [
          OutputKind.staticLibrary,
          OutputKind.sharedLibrary,
        ]) {
          final file = File.fromUri(
            directory.uri.resolve('$target-${kind.name}'),
          );
          await Linker(target).link([object], file, kind);
          final first = file.readAsBytesSync();
          await Linker(target).link([object], file, kind);
          expect(file.readAsBytesSync(), first);
        }
      }
    }
  });

  test(
    'invalid inputs preserve outputs and reject malformed library names',
    () async {
      final output = File.fromUri(directory.uri.resolve('preserved'))
        ..writeAsStringSync('previous');
      final other = _object(
        Target(
          target.operatingSystem == .macos ? .linux : .macos,
          target.architecture,
        ),
      );
      for (final input in [
        <ObjectFile>[],
        [object, other],
        [object, object],
      ]) {
        await expectLater(
          Linker(target).link(input, output, .sharedLibrary),
          throwsArgumentError,
        );
        expect(output.readAsStringSync(), 'previous');
      }
      await expectLater(
        Linker(target).link([object], output, .object),
        throwsArgumentError,
      );
      expect(() => Archive.encode([]), throwsArgumentError);
      expect(() => Archive.encode([object, other]), throwsArgumentError);
      for (final name in ['', 'bad\u0000name']) {
        expect(
          () => target.operatingSystem == .macos
              ? MachO.shared(object, name)
              : Elf.shared(object, name),
          throwsArgumentError,
        );
      }
      expect(directory.listSync().length, 1);
    },
  );
}

ObjectFile _object(Target target) {
  final bytes = target.architecture == .arm64
      ? [0xc0, 0x03, 0x5f, 0xd6]
      : [0xc3];
  return .new(target, bytes, [Symbol('entry', 0, bytes.length)]);
}
