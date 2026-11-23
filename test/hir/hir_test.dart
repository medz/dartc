import 'package:dartc/hir.dart';
import 'package:test/test.dart';

HirModule _module(HirTerminator? Function(HirBlock block) build) {
  final block = HirBlock();
  final end = build(block);
  if (end != null) block.end(end);
  return HirModule(HirFunction('main', block));
}

void main() {
  void rejects(String message, HirModule module) => test(
    'rejects $message',
    () {
      final matcher = throwsA(
        isA<HirError>().having((e) => e.message, 'message', contains(message)),
      );
      expect(() => verifyHir(module), matcher);
      expect(() => HirInterpreter(module), matcher);
    },
  );

  rejects('no terminator', _module((_) => null));
  rejects(
    'use of an undefined value',
    _module((block) {
      block.add(HirIntUnary(.negate, HirInt(1)));
      return HirReturn();
    }),
  );
  rejects('use of an undefined value', _module((_) => HirExit(HirInt(1))));
  rejects(
    'use of an undefined value',
    _module((block) {
      final late = HirInt(1);
      block.add(HirIntBinary(.add, late, late));
      block.add(late);
      return HirReturn();
    }),
  );
  rejects(
    'a value is defined twice',
    _module((block) {
      final value = block.add(HirInt(1));
      block.add(value);
      return HirReturn();
    }),
  );

  test('a block accepts one terminator and nothing after it', () {
    final block = HirBlock()..end(HirReturn());
    expect(() => block.end(HirReturn()), throwsStateError);
    expect(() => block.add(HirInt(1)), throwsStateError);
  });

  test('operators follow Dart', () {
    const min = -0x8000000000000000, max = 0x7fffffffffffffff;
    int? binary(HirIntOperator operator, int a, int b) => HirInterpreter(
      _module((block) {
        final left = block.add(HirInt(a)), right = block.add(HirInt(b));
        return HirExit(block.add(HirIntBinary(operator, left, right)));
      }),
    ).run();
    int? unary(HirIntPrefix operator, int a) => HirInterpreter(
      _module((block) {
        final operand = block.add(HirInt(a));
        return HirExit(block.add(HirIntUnary(operator, operand)));
      }),
    ).run();
    expect(binary(.add, max, 1), min);
    expect(binary(.subtract, min, 1), max);
    expect(binary(.multiply, max, 2), -2);
    expect(binary(.and, 12, 10), 8);
    expect(binary(.or, 12, 10), 14);
    expect(binary(.xor, 12, 10), 6);
    expect(unary(.negate, min), min);
    expect(unary(.negate, 3), -3);
    expect(unary(.complement, 3), -4);
  });

  test('returning is not exiting', () {
    expect(HirInterpreter(_module((_) => HirReturn())).run(), isNull);
  });

  test('prints every construct', () {
    final exits = _module((block) {
      final one = block.add(HirInt(-1));
      final sum = block.add(HirIntBinary(.add, one, one));
      return HirExit(block.add(HirIntUnary(.complement, sum)));
    });
    expect(printHir(exits), '''
main() {
  v0 = -1
  v1 = v0 + v0
  v2 = ~v1
  exit v2
}''');
    expect(printHir(_module((_) => HirReturn())), 'main() {\n  return\n}');
    final broken = _module((block) {
      block.add(HirIntUnary(.negate, HirInt(1)));
      return null;
    });
    expect(
      printHir(broken),
      'main() {\n  v0 = -<undefined>\n  <no terminator>\n}',
    );
  });
}
