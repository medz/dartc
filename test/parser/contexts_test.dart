import 'package:dartc/ast.dart';
import 'package:dartc/parser.dart';
import 'package:dartc/scanner.dart';
import 'package:dartc/source.dart';
import 'package:test/test.dart';

ParseResult<CompilationUnit> unit(String text) =>
    parseCompilationUnit(scan(SourceFile(Uri.parse('memory:context'), text)));

void main() {
  test('rejects jumps without the required enclosing statement', () {
    for (final (body, code) in [
      ('break;', 'break_outside_loop_or_switch'),
      ('continue;', 'invalid_continue_context'),
      ('continue missing;', 'invalid_continue_context'),
      ('label: { break; }', 'break_outside_loop_or_switch'),
      ('label: { continue label; }', 'invalid_continue_context'),
      ('switch (x) { case 1: continue; }', 'invalid_continue_context'),
      ('while (true) {} break;', 'break_outside_loop_or_switch'),
      ('switch (x) { default: break; } continue;', 'invalid_continue_context'),
      (
        'while (true) { void local() { break; } }',
        'break_outside_loop_or_switch',
      ),
      (
        'while (true) { final local = () { continue; }; }',
        'invalid_continue_context',
      ),
    ]) {
      final result = unit('void f() { $body }');
      expect(
        result.diagnostics.map((d) => d.code),
        contains('parser.$code'),
        reason: body,
      );
      expect(result.node.members, hasLength(1));
    }
  });

  test(
    'preserves legal jump contexts across statements and nested functions',
    () {
      for (final body in [
        'label: { break label; }',
        'while (true) { continue; break; }',
        'do { continue; break; } while (true);',
        'for (;;) { continue; break; }',
        'for (var x in xs) { continue; break; }',
        'switch (x) { case 1: continue next; next: case 2: break; }',
        'while (true) { switch (x) { default: continue; } break; }',
        'while (true) { void local() { while (true) { break; } } continue; }',
        'while (true) { final local = () { for (;;) { break; } }; continue; }',
        'while (true) { try { break; } finally { continue; } }',
      ]) {
        expect(unit('void f() { $body }').diagnostics, isEmpty, reason: body);
      }
    },
  );

  test('checks parameter modifiers in their declaration context', () {
    for (final text in [
      'void f(covariant int x) {}',
      'set value(covariant int x) {}',
      'void f() { void local(covariant int x) {} }',
      'class C { static void f(covariant int x) {} }',
      'extension E on int { void f(covariant int x) {} }',
      'class C { C(final int x); }',
      'class C { C(var x); }',
    ]) {
      expect(unit(text).hasErrors, isTrue, reason: text);
    }
    for (final text in [
      'class C { void f(covariant int x) {} }',
      'class C { set value(covariant int x) {} }',
      'class C { C(covariant int x); }',
      'class C(final int x);',
      'class C(var x);',
      'void f(void callback(covariant int x)) {}',
      'typedef F(covariant int x);',
    ]) {
      expect(unit(text).diagnostics, isEmpty, reason: text);
    }
  });

  test('checks setter signatures, member names and enum arguments', () {
    for (final text in [
      'set value() {}',
      'set value(int a, int b) {}',
      'set value([int a = 0]) {}',
      'set value({int a = 0}) {}',
      'class C { set value() {} }',
      'class C { int C; }',
      'class C { int get C => 0; }',
      'class C { set C(int value) {} }',
      'class C { void C() {} }',
      'class C { static covariant int value; }',
      'enum E { a<int>; }',
      'enum E { a.named; }',
      'mixin M { M(); }',
      'extension E on int { E(); }',
      'extension type E(int value) { void f(covariant int x) {} }',
    ]) {
      final result = unit(text);
      expect(result.hasErrors, isTrue, reason: text);
      expect(result.node.text, text);
    }
    for (final text in [
      'set value(int value) {}',
      'class C { C(); C.named(); factory C.from() = C; }',
      'extension E on int { static int get value => 1; }',
      'extension type E(int value) { E.named(this.value); }',
      'enum E { a, b(), c<int>.named(1); }',
    ]) {
      expect(unit(text).diagnostics, isEmpty, reason: text);
    }
  });

  test('leaves binding and semantic constraints to later analysis', () {
    for (final text in [
      'void f() { break missing; }',
      'void f() { rethrow; }',
      'void f(this.x) {}',
      'void f([int x = other()]) {}',
      'void f() { final g = (covariant int x) {}; }',
    ]) {
      expect(unit(text).diagnostics, isEmpty, reason: text);
    }
  });
}
