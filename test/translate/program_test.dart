import 'package:dartc/hir.dart';
import 'package:test/test.dart';

import '../support/compiler.dart';
import '../support/programs.dart';

void main() {
  programs('program');

  test('evaluates operands from left to right', () async {
    final module = await translate('void main() { 1 + 2 * -(~3); }');
    expect(printHir(module), '''
void start {
b0():
  v0 = main()
  return
}
reference main {
b0():
  v0 = 1
  v1 = 2
  v2 = 3
  v3 = ~v2
  v4 = -v3
  v5 = v1 * v4
  v6 = v0 + v5
  v7 = null
  return v7
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
}
