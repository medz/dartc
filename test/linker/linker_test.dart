import 'dart:ffi';
import 'dart:io';

import 'package:dartc/arm64.dart' as arm64;
import 'package:dartc/artifact.dart' as artifact;
import 'package:dartc/formats.dart';
import 'package:dartc/linker.dart';
import 'package:dartc/target.dart';
import 'package:dartc/x64.dart' as x64;
import 'package:test/test.dart';

artifact.ObjectFile functions(Target target, Map<String, int> values) {
  final code = <int>[], symbols = <artifact.Symbol>[];
  for (final MapEntry(:key, :value) in values.entries) {
    final List<int> body;
    if (target.architecture == .arm64) {
      final assembler = arm64.Assembler()
        ..loadImmediate(.x0, value)
        ..ret();
      body = assembler.takeBytes();
    } else {
      final assembler = x64.Assembler()
        ..loadImmediate(.rax, value)
        ..ret();
      body = assembler.takeBytes();
    }
    symbols.add(
      artifact.Symbol(
        target.operatingSystem == .macos ? '_$key' : key,
        code.length,
        body.length,
      ),
    );
    code.addAll(body);
  }
  return artifact.ObjectFile(target, code, symbols);
}

void main() {
  final target = Target.host();
  late Directory directory;
  setUp(() {
    Directory('build/linker').createSync(recursive: true);
    directory = Directory('build/linker').createTempSync('test-');
  });
  tearDown(() => directory.deleteSync(recursive: true));

  test('multiple objects link independently of the compiler', () async {
    final inputs = [
      functions(target, {'first': 40}),
      functions(target, {'second': 2}),
    ];
    for (final kind in [
      artifact.OutputKind.staticLibrary,
      artifact.OutputKind.sharedLibrary,
    ]) {
      final file = File.fromUri(
        directory.uri.resolve(
          kind == .staticLibrary
              ? 'values.a'
              : target.operatingSystem == .macos
              ? 'values.dylib'
              : 'values.so',
        ),
      );
      await Linker(target).link(inputs, file, kind);
      final executable = File.fromUri(directory.uri.resolve('host'));
      final linked = await Process.run('cc', [
        'test/linker/fixtures/host.c',
        file.path,
        '-o',
        executable.path,
        '-Wl,-rpath,${directory.absolute.path}',
        if (target.operatingSystem == .macos) ...[
          '-arch',
          target.architecture == .arm64 ? 'arm64' : 'x86_64',
        ],
      ]);
      expect(linked.exitCode, 0, reason: '${linked.stdout}${linked.stderr}');
      final ran = await Process.run(executable.absolute.path, []);
      expect(ran.exitCode, 0, reason: '${ran.stdout}${ran.stderr}');
    }
  });

  test(
    'large symbol tables resolve prefixes, Unicode names and missing names',
    () async {
      final values = {
        'prefix': -7,
        'prefix_more': 42,
        'π': 314,
        for (var i = 0; i < 700; i++) 'fn_$i': i,
      };
      final object = functions(target, values);
      final file = File.fromUri(directory.uri.resolve('symbols'));
      await Linker(target).link([object], file, .sharedLibrary);
      final library = DynamicLibrary.open(file.absolute.path);
      try {
        for (final MapEntry(:key, :value) in values.entries) {
          expect(
            library.lookupFunction<Int64 Function(), int Function()>(key)(),
            value,
            reason: key,
          );
        }
        expect(library.providesSymbol('prefi'), isFalse);
        expect(library.providesSymbol('fn_700'), isFalse);
      } finally {
        library.close();
      }
      if (target.operatingSystem == .macos) {
        final checked = await Process.run('/usr/bin/codesign', [
          '--verify',
          '--strict',
          file.path,
        ]);
        expect(
          checked.exitCode,
          0,
          reason: '${checked.stdout}${checked.stderr}',
        );
      }
    },
  );

  test('all targets encode deterministically without host linking', () async {
    for (final os in OperatingSystem.values) {
      for (final arch in Architecture.values) {
        final target = Target(os, arch);
        final object = functions(target, {'first': 40, 'second': 2});
        for (final kind in [
          artifact.OutputKind.staticLibrary,
          artifact.OutputKind.sharedLibrary,
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
      final object = functions(target, {'first': 40});
      final other = functions(
        Target(
          target.operatingSystem,
          target.architecture == .arm64 ? .x64 : .arm64,
        ),
        {'second': 2},
      );
      for (final input in [
        <artifact.ObjectFile>[],
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
