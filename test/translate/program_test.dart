import 'package:dartc/hir.dart';
import 'package:dartc/source.dart';
import 'package:dartc/translate.dart';
import 'package:test/test.dart';

import '../support/new_compiler.dart';

Future<HirModule> _files(Map<String, String> files) async {
  final directory = writeSources(files);
  return translateProgram(
    await loadProgram('${directory.path}/main.dart', sdk: hostSdk),
  );
}

void main() {
  /// Checks the code that a program using `dart:io` exits with.
  void exits(String name, String source, int? code) => test(name, () async {
    final module = await translate("import 'dart:io';\n$source");
    expect(HirInterpreter(module).run(), code);
  });

  /// Checks the code that the statements [body] exit with.
  void runs(String name, String body, int? code) =>
      exits(name, 'void main() { $body }', code);

  test('evaluates operands from left to right', () async {
    final module = await translate(
      "import 'dart:io';\nvoid main() { exit(1 + 2 * -(~3)); }",
    );
    expect(printHir(module), '''
void main {
b0():
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

  test('only the code that can run is kept', () async {
    final module = await translate(
      "import 'dart:io';\n"
      'void unused() {}\n'
      'void main() { exit(1); while (true) { unused(); } }',
    );
    expect(module.main.blocks, hasLength(1));
  });

  group('literals', () {
    for (final (text, value) in [
      ('0', 0),
      ('1_000', 1000),
      ('0xFF', 255),
      ('0xffffffffffffffff', -1),
      ('-9223372036854775808', -0x8000000000000000),
      ('-(0xffffffffffffffff)', 1),
      ('-0x8000000000000000', -0x8000000000000000),
      ('- 5', -5),
    ]) {
      runs(text, 'exit($text);', value);
    }
    runs('an int literal can be a double', '''
      double a = 1, b = -0;
      exit(a / 4 == 0.25 && 1 / b < 0 ? 1 : 0);''', 1);
    test('too large for an int', () async {
      for (final text in ['-0xffffffffffffffff', '9223372036854775808']) {
        await expectLater(
          translate("import 'dart:io';\nvoid main() { exit($text); }"),
          throwsA(isA<CompileFailure>()),
          reason: text,
        );
      }
    });
  });

  group('constants', () {
    exits(
      'top-level and local',
      '''
      const a = 3, b = a * 2.5, c = a > 2;
      void main() { const d = a ~/ 2; exit(c && b == 7.5 ? a * 10 + d : 0); }''',
      31,
    );
    runs(
      'of SDK classes',
      '''
      exit(double.infinity > double.maxFinite && double.nan != double.nan ? 1 : 0);''',
      1,
    );
    runs('as divisors and shifts', 'const n = 3; exit(100 ~/ n % n << n);', 0);
    test('of an imported library', () async {
      final module = await _files({
        'main.dart':
            "import 'dart:io';\nimport 'a.dart' as a;\n"
            'void main() { exit(a.x); }',
        'a.dart': 'const x = 12;',
      });
      expect(HirInterpreter(module).run(), 12);
    });
  });

  group('variables', () {
    runs('assignments nest inside others', '''
      var x = 0, y = 0, z = 0; if (1 < 2) { x = (y = 4); z = -(y += 1); }
      exit(x * 100 + y * 10 - z);''', 455);
    runs('assignments hide behind operators', '''
      var x = 0, y = 0; if (1 < 2) { x = -(y = 4); } exit(y * 10 - x);''', 44);
    runs('a variable may stay unassigned on one side', '''
      var n = 1; int x; if (n > 0) { x = 5; n += x; } exit(n);''', 6);
    runs('a constant of any type may go unused', 'const s = "a"; exit(3);', 3);
    runs('declared, assigned and stepped', '''
      var a = 1, b = 2; int c; c = a = b + 3; a += 2; b -= 1; c *= 2;
      exit(a * 1000 + b * 100 + c);''', 7110);
    runs('steps before and after', '''
      var y = 1; final z = y++ + y++ * ++y; y--; --y; exit(z * 10 + y);''', 92);
    runs(
      'compound assignment reads first',
      'int x = 3; x += (x = 5) + x; exit(x);',
      13,
    );
    runs('every compound operator', '''
      var x = 100; x -= 1; x *= 3; x ~/= 2; x %= 50; x <<= 4; x >>= 1; x |= 3;
      x &= 0x7f; x ^= 5; x >>>= 1; var d = 1.0; d += 1; d /= 4; d *= 3; d -= 1;
      var b = true; b &= false; b |= true; b ^= false;
      exit(d == 0.5 && b ? x : 0);''', _compound());
    exits('parameters can be assigned', '''
      int f(int a) { a += 1; a++; return a; }
      void main() { exit(f(5)); }''', 7);
    runs('inner variables hide outer ones', '''
      var x = 1; { var x = 2; x++; } exit(x);''', 1);
    runs('a variable may be assigned later', '''
      int x; bool b; if (1 < 2) { x = 5; b = true; } else { x = 6; b = false; }
      exit(b ? x : 0);''', 5);
  });

  group('branches', () {
    runs(
      'if without else',
      'var x = 1; if (x > 1) x = 9; if (x == 1) x = 4; exit(x);',
      4,
    );
    runs('else if', '''
      var x = 5; if (x < 3) { x = 0; } else if (x < 6) { x = 1; } else { x = 2; }
      exit(x);''', 1);
    runs('both sides leave', 'if (1 > 2) { exit(1); } else { exit(2); }', 2);
    runs(
      'conditional expressions',
      'var x = 3; exit(x > 2 ? (x > 5 ? 1 : 2) : 3);',
      2,
    );
    runs('assignments inside conditions survive', '''
      var x = 0; final y = (x = 4) > 3 ? x++ : x--; exit(x * 10 + y);''', 54);
    runs('&& and || stop early', '''
      var n = 0;
      final a = 1 > 2 && (n += 1) > 0; final b = 1 < 2 || (n += 10) > 0;
      final c = 1 < 2 && (n += 100) > 0; final d = 1 > 2 || (n += 1000) > 0;
      if (!a && b && c && d) exit(n);''', 1100);
  });

  group('loops', () {
    runs('break in each kind', '''
      var n = 0; while (true) { if (++n > 3) break; }
      do { if (++n > 6) break; } while (true);
      exit(n);''', 7);
    runs(
      'while',
      'var n = 0, i = 0; while (i < 5) { n += i; i++; } exit(n);',
      10,
    );
    runs('while that never runs', 'var n = 7; while (n < 0) n++; exit(n);', 7);
    runs('do', 'var n = 0; do { n++; } while (n < 5); exit(n);', 5);
    runs(
      'for',
      'var n = 0; for (var i = 0, j = 9; i < j; i++, j--) n += j - i; exit(n);',
      25,
    );
    runs(
      'for with an expression',
      'int i, n = 0; for (i = 2; i < 3; i++) n += i; exit(n * 10 + i);',
      23,
    );
    runs(
      'for without parts',
      'var n = 0; for (;;) { if (++n == 6) break; } exit(n);',
      6,
    );
    runs('continue in each kind', '''
      var n = 0;
      for (var i = 0; i < 6; i++) { if (i % 2 == 0) continue; n += i; }
      var j = 0; while (j < 6) { j++; if (j == 3) continue; n += 10; }
      var k = 0; do { k++; if (k == 2) continue; n += 100; } while (k < 4);
      exit(n);''', 359);
    runs('labels', '''
      var n = 0;
      outer: for (var i = 0; i < 5; i++) {
        for (var j = 0; j < 5; j++) {
          if (j == 3) continue outer;
          if (i == 3) break outer;
          n++;
        }
      }
      block: { n += 100; if (n > 50) break block; n += 1000; }
      exit(n);''', 109);
    runs('variables of an iteration are fresh', '''
      var n = 0;
      for (var i = 0; i < 3; i++) { int x; if (i == 1) { x = 5; } else { x = 1; } n += x; }
      exit(n);''', 7);
    runs('swapping needs both old values', '''
      var a = 1, b = 2; for (var i = 0; i < 3; i++) { final t = a; a = b; b = t; }
      exit(a * 10 + b);''', 21);
  });

  group('switch', () {
    runs('over double', '''
      var d = 1.0, n = 0; switch (d) { case 1: n += 1; default: n += 2; }
      d = 0; switch (d) { case -0.0: n += 10; default: n += 20; }
      exit(n);''', 11);
    const choose = '''
      int f(int x) {
        var r = 0;
        switch (x) {
          case 1:
          case -2:
            r = 10;
          case 3:
            r = 20;
            break;
          case 4:
            return 99;
          default:
            r = 30;
        }
        return r;
      }''';
    for (final (value, code) in [
      (1, 10),
      (-2, 10),
      (3, 20),
      (4, 99),
      (5, 30),
    ]) {
      exits('case $value', '$choose\nvoid main() { exit(f($value)); }', code);
    }
    runs(
      'without a default',
      'var n = 1; switch (n) { case 2: n = 5; } exit(n);',
      1,
    );
    runs(
      'over bool',
      'switch (1 < 2) { case true: exit(3); case false: exit(4); }',
      3,
    );
    runs('sharing the default', 'switch (9) { case 1: default: exit(8); }', 8);
    runs(
      'with an empty last case',
      'switch (9) { case 1: exit(1); case 9: } exit(2);',
      2,
    );
    runs('continue inside goes to the loop', '''
      var n = 0;
      for (var i = 0; i < 5; i++) { switch (i) { case 2: continue; case 3: break; } n += i; }
      exit(n);''', 8);
    runs(
      'its value is read once',
      '''
      var n = 1; switch (n++) { case 1: n += 10; case 2: n += 100; } exit(n);''',
      12,
    );
  });

  group('functions', () {
    exits('that never return, as values', '''
      Never stop(int x) => exit(x);
      int f(bool b) => b ? 1 : stop(6);
      void main() { final int x = f(true) + f(false); exit(x); }''', 6);
    exits('call each other', '''
      bool even(int n) => n == 0 || odd(n - 1);
      bool odd(int n) { if (n == 0) return false; return even(n - 1); }
      void main() { exit(even(10) ? 1 : 2); }''', 1);
    exits(
      'optional and named parameters',
      '''
      int f(int a, [int b = 2, int c = 3]) => a * 100 + b * 10 + c;
      int g({required int a, int b = 7, double c = 1}) => c == 1 ? a * 10 + b : 0;
      void main() { exit(f(1) + f(1, 5) + f(1, 5, 6) + g(b: 1, a: 2) + g(a: 3)); }''',
      123 + 153 + 156 + 21 + 37,
    );
    exits('arguments run in source order', '''
      int f({required int a, required int b}) => a * 10 + b;
      void main() { var n = 1; exit(f(b: n++, a: n++)); }''', 21);
    exits('without a result', '''
      void f(int x) { if (x > 3) return; exit(x); }
      void g() => f(2);
      void main() { f(5); g(); }''', 2);
    exits(
      'that never return',
      '''
      Never stop(int x) => exit(x);
      int f(bool b) => b ? 1 : stop(6);
      int g(bool b) { if (b) return 2; stop(7); }
      void main() { f(true); g(true); final int x = g(false); f(false); exit(x); }''',
      7,
    );
    exits('a conditional between effects', '''
      void f(int x) { exit(x); }
      void main() { 1 > 2 ? f(1) : f(2); }''', 2);
    exits('of doubles', '''
      double half(double x) => x / 2;
      double sum(double a, int b) => a + b;
      void main() { exit(sum(half(5), 2) == 4.5 ? 1 : 0); }''', 1);
    test('of other libraries and parts', () async {
      final module = await _files({
        'main.dart':
            "import 'dart:io';\nimport 'a.dart' as a;\npart 'p.dart';\n"
            'int f() => 1;\nvoid main() => exit(f() + a.f() + p());',
        'a.dart': 'int f() => 20;',
        'p.dart': "part of 'main.dart';\nint p() => 300;",
      });
      expect(HirInterpreter(module).run(), 321);
    });
    exits('main may call itself', '''
      var unusedGlobal = 1;
      const limit = 3;
      void main() { if (limit > 2) exit(4); main(); }''', 4);
  });

  group('numbers', () {
    runs(
      'harmless constants',
      'var x = 5; exit((x << 0) * 10 + x ~/ 1 + x % 1);',
      55,
    );
    runs('int meets double', '''
      var n = 0;
      if (1 + 0.5 == 1.5) n += 1; if (0.5 + 1 == 1.5) n += 2; if (7 / 2 == 3.5) n += 4;
      if (9007199254740993 == 9007199254740992.0) n += 8; if (1 < 1.5) n += 16;
      if (5 % 3.5 == 1.5) n += 32; if (-5.5 % 2 == 0.5) n += 64;
      exit(n);''', 127);
    runs(
      'bool operators',
      'var a = true; exit((a & false) | (a ^ false) && !(a == false) ? 1 : 0);',
      1,
    );
  });

  group('programs that just return', () {
    for (final source in [
      'void main() {}',
      'main() {}',
      'void main() { ; { 1 + 2; } }',
      'void main() { return; }',
      'int main() => 1 + 2;',
      'int main() { return 5; }',
      'void main() { assert(1 > 2, "unsupported in here"); }',
    ]) {
      exits(source, source, null);
    }
    exits('Never main', 'Never main() => exit(3);', 3);
  });

  group('nothing runs after', () {
    runs('exit', 'exit(1); exit(2);', 1);
    runs('exit in a block', '{ exit(1); } 5; exit(2);', 1);
    runs('return', 'return; exit(2);', null);
    runs('a loop without end', 'for (;;) { exit(3); } exit(4);', 3);
  });

  test('exit is recognized by what it refers to', () async {
    final prefixed = await translate(
      "import 'dart:io' as io;\nvoid main() { (io.exit(4)); }",
    );
    expect(HirInterpreter(prefixed).run(), 4);
    final own = await translate(
      'void exit(int code) {}\nvoid main() { exit(4); }',
    );
    expect(HirInterpreter(own).run(), isNull);
  });

  test('main must exist, in this library', () async {
    await expectLater(
      translate('void f() {}'),
      failsWith(['main.dart:1:1: The program has no main function.']),
    );
    final exported = await _files({
      'main.dart': "export 'other.dart';",
      'other.dart': "import 'dart:io';\nvoid main() => exit(8);",
    });
    expect(HirInterpreter(exported).run(), 8);
    final part = await _files({
      'main.dart': "import 'dart:io';\npart 'part.dart';",
      'part.dart': "part of 'main.dart';\nvoid main() => exit(6);",
    });
    expect(HirInterpreter(part).run(), 6);
  });

  group('not supported yet:', () {
    void reports(String source, String problem) => test(problem, () async {
      await expectLater(
        translate("import 'dart:io';\n$source"),
        failsWith(['main.dart:$problem']),
      );
    });

    const what = 'Not supported yet:';
    reports('void main(List<String> a) {}', '2:6: $what parameters of main.');
    reports(
      'void f<T>() {}\nvoid main() { f<int>(); }',
      '2:7: $what type parameters.',
    );
    reports(
      'Future<void> main() async {}',
      '2:21: $what async and generator functions.',
    );
    reports('external void main();', '2:21: $what a function without a body.');
    reports(
      'void f(num x) {}\nvoid main() { f(1); }',
      '2:6: $what a parameter of type num.',
    );
    reports(
      'int? f() => 1;\nvoid main() { f(); }',
      '2:6: $what a result of type int?.',
    );
    reports(
      'void main() { num x = 1; }',
      '2:19: $what a variable of type num.',
    );
    reports('void main() { int? x; }', '2:20: $what a variable of type int?.');
    reports(
      'void main() { late int x; x = 1; }',
      '2:15: $what late variables.',
    );
    reports('void main() { for (final x in [1]) {} }', '2:15: $what for-in.');
    reports('void main() { if (1 case 1) {} }', '2:21: $what if-case.');
    reports(
      'void main() { switch (1) { case < 2: } }',
      '2:28: $what this kind of case.',
    );
    reports(
      'void main() { switch (1) { case 1 when 1 < 2: } }',
      '2:28: $what this kind of case.',
    );
    reports(
      'void main() { switch (1) { a: case 1: continue a; } }',
      '2:28: $what a labeled case.',
    );
    reports(
      'void main() { void f() {} }',
      '2:15: $what function declaration statement.',
    );
    reports(
      'void main() { 1 == true; }',
      '2:15: $what operator == on these types.',
    );
    reports(
      'void main() { 1 < 2 ? 1 : 2.5; }',
      '2:15: $what a value of type num.',
    );
    reports('void main() { "a"; }', '2:15: $what simple string literal.');
    reports('void main() { 1.abs(); }', '2:15: $what method invocation.');
    reports(
      'void main() { exit(main.hashCode); }',
      '2:20: $what prefixed identifier.',
    );
    reports(
      'void main() { exit(1.hashCode); }',
      '2:20: $what property access.',
    );
    reports(
      "import 'dart:math';\nvoid main() { max(1, 2); }",
      '3:15: $what calling max of the SDK.',
    );
    reports(
      'const s = "a";\nvoid main() { s; }',
      '3:15: $what a constant of type String.',
    );
    reports(
      'void main() { true == 1; }',
      '2:15: $what operator == on these types.',
    );
    reports('void main() { 1 ?? 2; }', '2:15: $what using int as an object.');
    reports(
      'void f(int x) { x ??= 1; }\nvoid main() { f(1); }',
      '2:17: $what operator ??=.',
    );
    reports(
      'void main() { for (var (a, b) = (1, 2); a < b; a++) {} }',
      '2:20: $what for parts with pattern.',
    );
    reports(
      'void main() { switch (1) { case true: } }',
      '2:33: $what this kind of case.',
    );
    const printing = 'printing anything but a constant string';
    reports('void main() { print(1); }', '2:21: $what $printing.');
    reports(
      r'void main() { var x = 1; print("$x"); }',
      '2:32: $what $printing.',
    );
    reports('void main() { print("a" + "b"); }', '2:21: $what $printing.');
    reports('void main() { const x = 1; print(x); }', '2:34: $what $printing.');
    // Also where the code can never run.
  });
}

int _compound() {
  var x = 100;
  x -= 1;
  x *= 3;
  x ~/= 2;
  x %= 50;
  x <<= 4;
  x >>= 1;
  x |= 3;
  x &= 0x7f;
  x ^= 5;
  x >>>= 1;
  return x;
}
