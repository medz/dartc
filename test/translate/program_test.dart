import 'package:dartc/hir.dart';
import 'package:dartc/source.dart';
import 'package:dartc/translate.dart';
import 'package:test/test.dart';

import '../support/new_compiler.dart';

void main() {
  Future<void> prints(String source, String hir) async =>
      expect(printHir(await translate(source)), hir);

  test('evaluates operands from left to right', () async {
    await prints("import 'dart:io';\nvoid main() { exit(1 + 2 * -(~3)); }", '''
main() {
  v0 = 1
  v1 = 2
  v2 = 3
  v3 = ~v2
  v4 = -v3
  v5 = v1 * v4
  v6 = v0 + v5
  exit v6
}''');
  });

  test('every operator', () async {
    final module = await translate(
      "import 'dart:io';\n"
      'void main() => exit(((7 + 8) * 3 - 1 & 60 | 3) ^ 5);',
    );
    expect(HirInterpreter(module).run(), ((7 + 8) * 3 - 1 & 60 | 3) ^ 5);
  });

  test('literal forms', () async {
    for (final (text, value) in [
      ('0', 0),
      ('1_000', 1000),
      ('0xFF', 255),
      ('0xffffffffffffffff', -1),
      ('9223372036854775807', 0x7fffffffffffffff),
      ('-9223372036854775808', -0x8000000000000000),
      ('-(0xffffffffffffffff)', 1),
      ('-0x8000000000000000', -0x8000000000000000),
      ('- 5', -5),
    ]) {
      final module = await translate(
        "import 'dart:io';\nvoid main() { exit($text); }",
      );
      expect(HirInterpreter(module).run(), value, reason: text);
    }
  });

  test('literals too large for an int are errors, as officially', () async {
    for (final text in ['-0xffffffffffffffff', '9223372036854775808']) {
      await expectLater(
        translate("import 'dart:io';\nvoid main() { exit($text); }"),
        throwsA(isA<CompileFailure>()),
        reason: text,
      );
    }
  });

  test('a program may just return', () async {
    for (final source in [
      'void main() {}',
      'main() {}',
      'void main() { ; { 1 + 2; } }',
      'void main() { return; }',
      'int main() => 1 + 2;',
      'Never main() => exit(3);',
    ]) {
      final module = await translate("import 'dart:io';\n$source");
      final exits = source.contains('exit');
      expect(HirInterpreter(module).run(), exits ? 3 : null, reason: source);
    }
  });

  test('nothing runs after exit or return', () async {
    for (final (body, value) in [
      ('exit(1); exit(2);', 1),
      ('{ exit(1); } 5; exit(2);', 1),
      ('return; exit(2);', null),
    ]) {
      final module = await translate(
        "import 'dart:io';\nvoid main() { $body }",
      );
      expect(HirInterpreter(module).run(), value, reason: body);
    }
  });

  test('exit is recognized by what it refers to', () async {
    final prefixed = await translate(
      "import 'dart:io' as io;\nvoid main() { (io.exit(4)); }",
    );
    expect(HirInterpreter(prefixed).run(), 4);
    await expectLater(
      translate('void exit(int code) {}\nvoid main() { exit(4); }'),
      failsWith(['main.dart:2:15: Not supported yet: method invocation.']),
    );
    await expectLater(
      translate(
        "import 'dart:io';\nextension on int { void exit(int c) {} }\n"
        'void main() { 1.exit(4); exitCode; }',
      ),
      failsWith(['main.dart:3:15: Not supported yet: method invocation.']),
    );
  });

  test('main may be in a part', () async {
    final directory = writeSources({
      'main.dart': "import 'dart:io';\npart 'part.dart';",
      'part.dart': "part of 'main.dart';\nvoid f() {}\nvoid main() => exit(6);",
    });
    final library = await loadLibrary(
      '${directory.path}/main.dart',
      sdk: hostSdk,
    );
    expect(HirInterpreter(translateProgram(library)).run(), 6);
  });

  test('main must exist, in this library', () async {
    await expectLater(
      translate('void f() {}'),
      failsWith(['main.dart:1:1: The program has no main function.']),
    );
    final directory = writeSources({
      'main.dart': "export 'other.dart';",
      'other.dart': 'void main() {}',
    });
    final library = await loadLibrary(
      '${directory.path}/main.dart',
      sdk: hostSdk,
    );
    expect(
      () => translateProgram(library),
      failsWith([
        'main.dart:1:1: Not supported yet: main from another library.',
      ]),
    );
  });

  group('not supported yet:', () {
    void reports(String source, String problem) => test(problem, () async {
      await expectLater(
        translate("import 'dart:io';\n$source"),
        failsWith(['main.dart:$problem']),
      );
    });

    const what = 'Not supported yet:';
    reports('void main(List<String> a) {}', '2:10: $what parameters.');
    reports('void main<T>() {}', '2:10: $what type parameters.');
    reports(
      'Future<void> main() async {}',
      '2:21: $what async and generator functions.',
    );
    reports('external void main();', '2:21: $what a function without a body.');
    reports(
      'void main() {\n  var x = 1;\n}',
      '3:3: $what variable declaration statement.',
    );
    reports('void main() { if (true) {} }', '2:15: $what if statement.');
    reports('int main() { return 1; }', '2:14: $what return statement.');
    reports('void main() { 1 ~/ 2; }', '2:15: $what operator ~/.');
    reports('void main() { 1 << 2; }', '2:15: $what operator <<.');
    reports('void main() { 1 == 2; }', '2:15: $what operator ==.');
    reports('void main() { !true; }', '2:15: $what operator !.');
    reports('void main() { 1 + 2.0; }', '2:19: $what operands of type double.');
    reports('void main() { 2.0 + 1; }', '2:15: $what operands of type double.');
    reports('void main() { -2.0; }', '2:16: $what operands of type double.');
    reports('double main() => 1;', '2:18: $what operands of type double.');
    reports('void main() { "a"; }', '2:15: $what simple string literal.');
    reports(
      'void main() { exit(main.hashCode); }',
      '2:20: $what prefixed identifier.',
    );
    // Also where the code can never run.
    reports('void main() { exit(1); 1 ~/ 2; }', '2:24: $what operator ~/.');
  });
}
