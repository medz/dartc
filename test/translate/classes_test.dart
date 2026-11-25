import 'package:dartc/hir.dart';
import 'package:test/test.dart';

import '../support/compiler.dart';
import '../support/programs.dart';

void main() {
  programs('classes');

  test('only what can be reached is translated', () async {
    final module = await translate('''
      class A { void f() => print('A'); void unused() { [1]; } }
      class B extends A { @override void f() { [2]; } }
      class C { void f() { [3]; } }
      void main() { A().f(); if (1 > 2) other(null); }
      void other(C? c) => c?.f();
    ''');
    final names = module.classes.map((class_) => class_.name);
    expect(names, contains('A'));
    expect(names, isNot(anyOf(contains('B'), contains('C'))));
    expect((HirInterpreter(module)..run()).output, 'A\n');
  });
}
