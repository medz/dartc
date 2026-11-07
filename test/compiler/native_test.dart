import 'dart:ffi';
import 'dart:io';

import 'package:dartc/artifact.dart';
import 'package:dartc/cli.dart';
import 'package:dartc/compiler.dart';
import 'package:dartc/formats.dart';
import 'package:dartc/linker.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import 'fixtures/arithmetic.dart' as sdk;

void main() {
  const source = 'test/compiler/fixtures/arithmetic.dart';
  final target = Target.host();
  late CompiledLibrary library;
  late Directory directory;

  setUpAll(() async {
    Directory('build/domain-foundations').createSync(recursive: true);
    directory = Directory('build/domain-foundations').createTempSync('native-');
    library = await Compiler(target).compile([source]);
  });
  tearDownAll(() => directory.deleteSync(recursive: true));

  for (final kind in OutputKind.values) {
    for (final language in ['c', 'c++']) {
      test('$kind links and executes from $language', () async {
        final extension = switch (kind) {
          .object => 'o',
          .staticLibrary => 'a',
          .sharedLibrary => target.operatingSystem == .macos ? 'dylib' : 'so',
        };
        final output = File.fromUri(
          directory.uri.resolve('arithmetic.$extension'),
        );
        await library.write(
          output,
          kind: kind,
          header: File.fromUri(directory.uri.resolve('generated.h')),
        );
        final executable = File.fromUri(directory.uri.resolve('host'));
        final args = [
          '-x',
          language,
          '-I',
          directory.path,
          'test/compiler/fixtures/host.c',
          '-x',
          'none',
          output.path,
          '-o',
          executable.path,
          '-Wl,-rpath,${directory.absolute.path}',
          if (target.operatingSystem == .macos) ...[
            '-arch',
            target.architecture == .arm64 ? 'arm64' : 'x86_64',
          ],
        ];
        final linked = await Process.run('cc', args);
        expect(linked.exitCode, 0, reason: '${linked.stdout}${linked.stderr}');
        final ran = await Process.run(executable.absolute.path, []);
        expect(ran.exitCode, 0, reason: '${ran.stdout}${ran.stderr}');
        expect(ran.stdout, 'native functions: ok\n');
      });
    }
  }

  test('formats reject the wrong target and write recognizable headers', () {
    final bytes = target.operatingSystem == .macos
        ? MachO.encode(library.object)
        : Elf.encode(library.object);
    expect(
      bytes.take(4),
      target.operatingSystem == .macos
          ? [0xcf, 0xfa, 0xed, 0xfe]
          : [0x7f, 0x45, 0x4c, 0x46],
    );
    expect(
      () => target.operatingSystem == .macos
          ? Elf.encode(library.object)
          : MachO.encode(library.object),
      throwsArgumentError,
    );
  });

  test('failed linking preserves an existing output', () async {
    final output = File.fromUri(directory.uri.resolve('preserved'))
      ..writeAsStringSync('previous');
    await expectLater(
      Linker(target)
          .link([library.object, library.object], output, .sharedLibrary),
      throwsArgumentError,
    );
    expect(output.readAsStringSync(), 'previous');
  });

  test(
    'native arithmetic agrees with the SDK at signed integer boundaries',
    () async {
      final file = File.fromUri(
        directory.uri.resolve(
          'differential.${target.operatingSystem == .macos ? 'dylib' : 'so'}',
        ),
      );
      await library.write(file, kind: .sharedLibrary);
      final native = DynamicLibrary.open(file.absolute.path);
      try {
        final add = native
            .lookupFunction<
              Int64 Function(Int64, Int64),
              int Function(int, int)
            >('native_add');
        final reverse = native
            .lookupFunction<
              Int64 Function(Int64, Int64),
              int Function(int, int)
            >('reverse');
        final twice = native
            .lookupFunction<Int64 Function(Int64), int Function(int)>('twice');
        final increment = native
            .lookupFunction<Int64 Function(Int64), int Function(int)>(
              'increment',
            );
        const values = [-0x8000000000000000, -1, 0, 42, 0x7fffffffffffffff];
        for (final a in values) {
          expect(twice(a), sdk.twice(a));
          expect(increment(a), sdk.increment(a));
          for (final b in values) {
            expect(add(a, b), sdk.add(a, b));
            expect(reverse(a, b), sdk.reverse(a, b));
          }
        }
      } finally {
        native.close();
      }
    },
  );

  test(
    'source files and colliding output paths cannot be overwritten',
    () async {
      final before = File(source).readAsStringSync();
      await expectLater(library.write(File(source)), throwsArgumentError);
      expect(File(source).readAsStringSync(), before);
      await expectLater(
        library.write(File('lib/src/export/annotation.dart')),
        throwsArgumentError,
      );
      final output = File.fromUri(directory.uri.resolve('collision'));
      await expectLater(
        library.write(output, header: output),
        throwsArgumentError,
      );
      expect(output.existsSync(), isFalse);
      final alias = Link.fromUri(directory.uri.resolve('alias'))
        ..createSync(directory.absolute.path);
      try {
        await expectLater(
          library.write(output, header: File('${alias.path}/collision')),
          throwsArgumentError,
        );
      } finally {
        alias.deleteSync();
      }
    },
  );

  test(
    'unsupported operations and signatures fail before writing output',
    () async {
      await expectLater(
        Compiler(target).compile(['test/compiler/fixtures/unsupported.dart']),
        throwsUnsupportedError,
      );
      await expectLater(
        Compiler(target)
            .compile(['test/compiler/fixtures/wrong_signature.dart']),
        throwsArgumentError,
      );
      await expectLater(
        Compiler(target)
            .compile(['test/compiler/fixtures/nullable_signature.dart']),
        throwsUnsupportedError,
      );
      await expectLater(
        Compiler(target)
            .compile(['test/compiler/fixtures/invalid_dependency.dart']),
        throwsFormatException,
      );
    },
  );

  test('CLI reports usage errors and writes a native object', () async {
    final output = StringBuffer(), errors = StringBuffer();
    final command = CompilerCommand(output, errors);
    expect(await command.run(['--help']), 0);
    expect(output.toString(), contains('Usage: dartc'));
    expect(await command.run([source, '--kind', 'unknown']), 64);
    expect(errors.toString(), contains('Unknown output kind'));
    final file = File.fromUri(directory.uri.resolve('cli.o'));
    expect(await command.run([source, '-o', file.path]), 0);
    expect(file.lengthSync(), greaterThan(library.object.code.length));
  });
}
