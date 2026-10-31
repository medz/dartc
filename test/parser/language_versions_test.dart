import 'package:dartc/ast.dart';
import 'package:dartc/parser.dart';
import 'package:dartc/scanner.dart';
import 'package:dartc/source.dart';
import 'package:test/test.dart';

ScanResult input(String text) =>
    scan(SourceFile(Uri.parse('memory:version'), text));
ParseResult<CompilationUnit> unit(String text, LanguageVersion version) =>
    parseCompilationUnit(input(text), languageVersion: version);

void main() {
  test('version values compare by major and minor', () {
    expect(
      const LanguageVersion(3, 9).compareTo(const LanguageVersion(3, 10)),
      lessThan(0),
    );
    expect(
      const LanguageVersion(3, 0).compareTo(const LanguageVersion(2, 19)),
      greaterThan(0),
    );
    expect(const LanguageVersion(3, 13), LanguageVersion.current);
    expect(
      const LanguageVersion(3, 13).hashCode,
      LanguageVersion.current.hashCode,
    );
    expect(LanguageVersion.current.toString(), '3.13');
  });

  test('checks each versioned syntax at its release boundary', () {
    for (final (major, minor, text) in [
      (2, 13, 'typedef F = int;'),
      (2, 14, '@A<int>() void f() {}'),
      (2, 14, 'void f() { x >>>= 1; final y = x >>> 1; }'),
      (2, 15, 'void f() { final x = f<int>; final y = C.new; }'),
      (2, 15, 'void f() { final x = C<int>.named; }'),
      (2, 17, 'class C extends B { C(super.x); }'),
      (2, 17, 'void f() { g(x: 1, 2); }'),
      (2, 17, 'enum E { a; void f() {} }'),
      (2, 19, 'library;'),
      (3, 0, 'base class C {}'),
      (3, 0, 'base mixin M {}'),
      (3, 0, 'mixin class M {}'),
      (3, 0, 'final x = (1, name: 2);'),
      (3, 0, 'typedef F = (int, {String name});'),
      (3, 0, 'void f() { final (x, y) = value; }'),
      (3, 0, 'void f() { if (x case int y) {} }'),
      (3, 0, 'void f() { final x = switch (y) { _ => 0 }; }'),
      (3, 3, 'extension type C(int x) {}'),
      (3, 6, 'final x = 1_000; final y = 1.0_1;'),
      (3, 8, 'final x = [?value];'),
      (3, 8, 'final x = {?key: ?value};'),
      (3, 10, 'C f() => .named();'),
      (3, 13, 'class C(final int x) {}'),
      (3, 13, 'class C;'),
      (3, 13, 'mixin M;'),
      (3, 13, 'extension E on int;'),
      (3, 13, 'class C { new(); }'),
      (3, 13, 'class C { factory named() = D; }'),
    ]) {
      final version = LanguageVersion(major, minor);
      final previous = minor == 0
          ? const LanguageVersion(2, 19)
          : LanguageVersion(major, minor - 1);
      final enabled = unit(text, version);
      expect(enabled.diagnostics, isEmpty, reason: '$version: $text');
      final disabled = unit(text, previous);
      expect(
        disabled.diagnostics.map((d) => d.code),
        contains('parser.language_feature_disabled'),
        reason: '$previous: $text',
      );
      expect(disabled.node.text, text);
    }
  });

  test('retains older function aliases, generic calls and switch cases', () {
    for (final text in [
      'typedef F = int Function(int value);',
      'typedef F = int Function()?;',
      'void f() { g<int>(); C<int>.named(); }',
      'class C { factory C() = D; factory C.named() = D; }',
      'void f() { switch (x) { case 1 + 2: break; case C.value: break; default: break; } }',
      'void f() { switch (x) { case 1 when true: break; } }',
    ]) {
      expect(
        unit(text, const LanguageVersion(2, 12)).diagnostics,
        isEmpty,
        reason: text,
      );
    }
    expect(
      unit(
        'typedef F = A<B<C<int>>>;',
        const LanguageVersion(2, 13),
      ).diagnostics,
      isEmpty,
    );
  });

  test('every standalone entry checks the selected language version', () {
    const version = LanguageVersion(2, 19);
    final results = <ParseResult<AstNode>>[
      parseExpression(input('(1, 2)'), languageVersion: version),
      parseStatement(input('final (a, b) = value;'), languageVersion: version),
      parseTypeAnnotation(input('(int, int)'), languageVersion: version),
      parseFormalParameterList(
        input('((int, int) value)'),
        languageVersion: version,
      ),
      parseFunctionBody(input('=> (1, 2);'), languageVersion: version),
      parsePattern(input('[var x]'), languageVersion: version),
    ];
    expect(results.every((r) => r.hasErrors), isTrue);
  });

  test('caller selects the version and input comments remain untouched', () {
    final source = input('// @dart=2.19\nfinal value = (1, 2);');
    final before = [...source.comments];
    expect(parseCompilationUnit(source).diagnostics, isEmpty);
    expect(
      parseCompilationUnit(
        source,
        languageVersion: const LanguageVersion(2, 19),
      ).hasErrors,
      isTrue,
    );
    expect(source.comments, orderedEquals(before));
  });

  test('unsupported versions return diagnostics with a recoverable tree', () {
    for (final version in [
      const LanguageVersion(2, 11),
      const LanguageVersion(2, 20),
      const LanguageVersion(4, 0),
      const LanguageVersion(3, -1),
    ]) {
      final result = unit('void f() {}', version);
      expect(result.node.members, hasLength(1));
      expect(
        result.diagnostics.map((d) => d.code),
        contains('parser.unsupported_language_version'),
      );
    }
  });
}
