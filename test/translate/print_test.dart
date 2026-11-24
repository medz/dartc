import 'package:dartc/hir.dart';
import 'package:test/test.dart';

import '../support/compiler.dart';

void main() {
  void prints(String name, String source, String output) =>
      test(name, () async {
        final interpreter = HirInterpreter(await translate(source))..run();
        expect(interpreter.output, output);
      });

  prints('literals', r'''
void main() {
  print('a');
  print("b" 'c');
  print(r'\n');
  print("""d
e""");
  print('\u{1F600}\x41');
  print(('f'));
  print('');
}''', 'a\nbc\n\\n\nd\ne\n\u{1F600}A\nf\n\n');

  prints('constants', r'''
const a = 'x', b = '$a-$a';
class C { static const c = 'z'; }
void main() {
  const d = 'l' 'm';
  print(a);
  print(b);
  print('$b$d${(a)}');
  print(C.c);
  print('${C.c}!');
}''', 'x\nx-x\nx-xlmx\nz\nz!\n');

  prints('in order and only where reached', '''
void f(int n) { if (n == 0) return; print('in'); f(n - 1); print('out'); }
void main() { f(2); if (1 > 2) print('never'); print('end'); }
''', 'in\nin\nout\nout\nend\n');

  prints('a print of the program itself is an ordinary call', '''
import 'dart:core' as core;
void print(core.int x) { core.print('mine'); }
void main() { print(1); }
''', 'mine\n');
}
