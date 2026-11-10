@Tags(['assets', 'native'])
library;

import 'dart:io';

import 'package:dartc/compiler.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  final compiler = Compiler(Target.host());

  test(
    'compilation rejects unsupported operations and invalid signatures',
    () async {
      await expectLater(
        compiler.compile(['test/compiler/fixtures/wrong_signature.dart']),
        throwsArgumentError,
      );
      await expectLater(
        compiler.compile(['test/compiler/fixtures/nullable_signature.dart']),
        throwsUnsupportedError,
      );
      for (final (fixture, error) in [
        ('wrong_pointer_signature', throwsArgumentError),
        ('nullable_pointer', throwsArgumentError),
        ('unsupported_pointer', throwsUnsupportedError),
        ('floating_modulo', throwsUnsupportedError),
      ]) {
        await expectLater(
          compiler.compile(['test/compiler/fixtures/$fixture.dart']),
          error,
        );
      }
      await expectLater(
        compiler.compile(['test/compiler/fixtures/invalid_dependency.dart']),
        throwsFormatException,
      );
    },
  );

  test(
    'SDK error branches still require their native implementations',
    () async {
      await expectLater(
        compiler.compile(['test/compiler/fixtures/sdk_functions.dart']),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'missing error constructor',
            'Native body unavailable: range',
          ),
        ),
      );
    },
  );

  test(
    'compilation owns final bytes and keeps the library name across writes',
    () async {
      final assets = NativeAssets(Target.host());
      final expected = assets.library('compiler/arithmetic');
      final result = await compiler.compile([
        'test/compiler/fixtures/arithmetic.dart',
      ], output: .sharedLibrary(expected.uri.pathSegments.last));
      expect(result.bytes, expected.readAsBytesSync());
      expect(() => result.bytes[0] = 0, throwsUnsupportedError);
      expect(
        result.header,
        assets.file('compiler/arithmetic.h').readAsStringSync(),
      );
      final directory = (Directory(
        'build/test',
      )..createSync(recursive: true)).createTempSync('compilation-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final header = File.fromUri(directory.uri.resolve('api.h'));
      for (final name in ['first-name', 'second-name']) {
        final output = File.fromUri(directory.uri.resolve(name));
        await result.write(output, header: header);
        expect(output.readAsBytesSync(), result.bytes);
        expect(header.readAsStringSync(), result.header);
      }
    },
  );

  test('invalid shared library identities fail during compilation', () async {
    for (final name in ['', 'bad\u0000name']) {
      await expectLater(
        compiler.compile([
          'test/compiler/fixtures/arithmetic.dart',
        ], output: .sharedLibrary(name)),
        throwsArgumentError,
      );
    }
  });

  test(
    'source files and colliding output paths cannot be overwritten',
    () async {
      const source = 'test/compiler/fixtures/arithmetic.dart';
      final library = await compiler.compile([source]);
      final before = File(source).readAsStringSync();
      await expectLater(library.write(File(source)), throwsArgumentError);
      expect(File(source).readAsStringSync(), before);
      await expectLater(
        library.write(File('lib/src/interop/annotation.dart')),
        throwsArgumentError,
      );
      final directory = (Directory(
        'build/test',
      )..createSync(recursive: true)).createTempSync('compiler-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final output = File.fromUri(directory.uri.resolve('collision'));
      await expectLater(
        library.write(output, header: output),
        throwsArgumentError,
      );
      expect(output.existsSync(), isFalse);
      final alias = Link.fromUri(directory.uri.resolve('alias'))
        ..createSync(directory.absolute.path);
      await expectLater(
        library.write(output, header: File('${alias.path}/collision')),
        throwsArgumentError,
      );
    },
  );
}
