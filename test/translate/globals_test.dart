import 'package:test/test.dart';

import '../support/compiler.dart';
import '../support/programs.dart';

void main() {
  programs('globals');

  group('only what needs it', () {
    test('initializes lazily', () async {
      final module = await translate('''
        class A { const A(); }
        int a = 1; int b = -1; double c = 1; bool d = false;
        A? e; A f = const A(); const k = A(); A g = k; A h = A();
        void main() { a; b; c; d; e; f; g; h; }
      ''');
      final own = RegExp(r'^[a-h]( is set)?$');
      expect(module.globals.map((global) => global.name).where(own.hasMatch), [
        'a',
        'b',
        'c',
        'd',
        'e',
        'f',
        'g',
        'h',
        'h is set',
      ]);
      expect(
        module.functions.map((function) => function.name).where(own.hasMatch),
        ['h'],
      );
    });

    test('lists what the program uses', () async {
      final module = await translate('''
        class A { const A(); }
        int a = 1, unused = 2;
        const k = A();
        void main() { a; }
      ''');
      expect(module.globals.single.name, 'a');
      expect(module.classes, isEmpty);
    });
  });
}
