import 'package:test/test.dart';

import '../support/compiler.dart';
import '../support/programs.dart';

void main() {
  programs('dynamic');

  test('what has no member is told by one function for all classes', () async {
    final module = await translate('''
      class A {}
      class B {}
      class C { void foo(int a, int b) {} }
      class D { void foo(String a, int b) {} }
      class E extends C {}
      void main() {
        for (final dynamic d in [A(), B(), C(), D(), E(), null, () {}]) {
          d.foo(1);
          d.foo;
          d.foo = 1;
          d.bar();
        }
      }
    ''');
    int count(String name) =>
        module.functions.where((f) => f.name == name).length;
    // A call tells whether there is no foo, or what it takes.
    expect(count('no foo'), 3 + 2);
    expect(count('no bar'), 1);
  });
}
