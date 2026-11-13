import 'dart:io';

import 'package:dartc/frontend.dart';
import 'package:test/test.dart';

void main() {
  const mapping = '''
import 'dart:ffi';
@AbiSpecificIntegerMapping({Abi.macosArm64: Int32(), Abi.linuxArm64: Int64()})
''';
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('dartc-ffi-'));
  tearDown(() => directory.deleteSync(recursive: true));

  Future<void> check(String source) async {
    final file = File('${directory.path}/entry.dart')
      ..writeAsStringSync(source);
    await AnalysisSession([file.path]).use((_) {});
  }

  for (final (name, declaration) in [
    (
      'empty body',
      'final class const NativeWord() extends AbiSpecificInteger;',
    ),
    (
      'explicit super initializer',
      'final class const NativeWord() extends AbiSpecificInteger { this : super(); }',
    ),
    (
      'constructor assertions',
      'final class const NativeWord([int value = 0]) extends AbiSpecificInteger { this : assert(value >= 0); }',
    ),
  ]) {
    test('accepts ABI integer primary constructor with $name', () async {
      await check('$mapping$declaration');
    });
  }

  for (final (name, declaration) in [
    (
      'non-const constructor',
      'final class NativeWord() extends AbiSpecificInteger;',
    ),
    (
      'type parameters',
      'final class const NativeWord<T>() extends AbiSpecificInteger;',
    ),
    (
      'declaring parameter',
      'final class const NativeWord(final int value) extends AbiSpecificInteger;',
    ),
    (
      'field',
      'final class const NativeWord() extends AbiSpecificInteger { final int value = 0; }',
    ),
    (
      'static field',
      'final class const NativeWord() extends AbiSpecificInteger { static const value = 0; }',
    ),
    (
      'method',
      'final class const NativeWord() extends AbiSpecificInteger { int read() => 0; }',
    ),
    (
      'getter',
      'final class const NativeWord() extends AbiSpecificInteger { int get value => 0; }',
    ),
    (
      'extra constructor',
      'final class const NativeWord() extends AbiSpecificInteger { const new other() : this(); }',
    ),
    (
      'ordinary constructor with field',
      'final class NativeWord extends AbiSpecificInteger { const new(); final int value = 0; }',
    ),
  ]) {
    test('rejects ABI integer $name before consumption', () async {
      await expectLater(
        check(
          '// ignore_for_file: abi_specific_integer_invalid\n$mapping$declaration',
        ),
        throwsFormatException,
      );
    });
  }

  test('preserves mapping and unrelated static errors', () async {
    const declaration =
        'final class const NativeWord() extends AbiSpecificInteger;';
    for (final source in [
      "import 'dart:ffi'; $declaration",
      "import 'dart:ffi'; @AbiSpecificIntegerMapping({Abi.macosArm64: Double()}) $declaration",
      '$mapping$declaration int invalid() => "wrong";',
    ]) {
      await expectLater(check(source), throwsFormatException);
    }
  });
}
