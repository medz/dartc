import 'dart:io';

import 'package:dartc/compiler.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

void main() {
  final compiler = Compiler(Target.host());

  test(
    'compilation rejects unsupported operations and invalid signatures',
    () async {
      await expectLater(
        compiler.compile(['test/compiler/fixtures/unsupported.dart']),
        throwsUnsupportedError,
      );
      await expectLater(
        compiler.compile([
          'test/compiler/fixtures/unsupported_control_flow.dart',
        ]),
        throwsUnsupportedError,
      );
      await expectLater(
        compiler.compile(['test/compiler/fixtures/wrong_signature.dart']),
        throwsArgumentError,
      );
      await expectLater(
        compiler.compile(['test/compiler/fixtures/nullable_signature.dart']),
        throwsUnsupportedError,
      );
      await expectLater(
        compiler.compile(['test/compiler/fixtures/invalid_dependency.dart']),
        throwsFormatException,
      );
    },
  );

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
