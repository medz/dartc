import 'package:test/test.dart';

import 'expectations.dart';

void main() {
  test('comments tell what a program does', () {
    final found = Expectations.of(r'''
// long
void main() {
  print(1); // expect: 1
  for (var i = 0; i < 2; i++) {
    print('');
  }
  // expect:
  // expect:
  print(' a "b"\n'); // expect: " a \"b\""
  // expect:
  throw 'c';
}
// stderr: Unhandled exception:
// stderr: c
// exit: 255
''');
    expect(found.output, ['1', '', '', ' a "b"', '']);
    expect(found.errors, ['Unhandled exception:', 'c']);
    expect(found.exitCode, 255);
    expect((found.isLong, found.isTold, found.isRefused), (true, true, false));
  });

  test('comments tell where a program is refused', () {
    final found = Expectations.of('''
external int x; // error 14: one

f() {

  // error 3: two
''');
    expect(found.problems, ['main.dart:1:14: one', 'main.dart:3:3: two']);
    expect(found.isRefused, isTrue);
    expect(Expectations.of('// error: three').elsewhere, 'three');
  });

  test('comments that tell nothing are kept', () {
    const source = '''
// long
f(); // A comment. // expect nothing
// Another.
g(); // error 1: kept
''';
    expect(Expectations.of('// A comment.').isTold, isFalse);
    expect(Expectations.removedFrom(source), source);
    expect(
      Expectations.removedFrom('f(); // expect: 1\n// exit: 2\ng();\n'),
      'f();\ng();\n',
    );
  });

  test('any line can be told', () {
    for (final text in ['', 'a', ' a', 'a ', '"a"', 'a\r', '\x00', 'é // b']) {
      final comment = Expectations.expect(text);
      expect(comment, isNot(contains('\n')));
      expect(Expectations.of('f(); $comment').output, [text]);
    }
    expect(Expectations.linesOf('a\n\nb\n'), ['a', '', 'b']);
    expect(() => Expectations.linesOf('a\nb'), throwsFormatException);
    expect(Expectations.linesOf(''), isEmpty);
  });
}
