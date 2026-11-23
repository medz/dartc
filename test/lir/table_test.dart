import 'package:dartc/lir.dart';
import 'package:test/test.dart';

import 'support.dart';

final _unary = LirSignature([.i64], .i64);

/// Calls an entry of the table `t` with 10.
LirFunction _caller() => function('call', [.i64], .i64, (block, p) {
  final table = block.add(SymbolAddress('t'));
  final at = block.add(IntBinary(.shl, p[0], block.add(ConstInt(2))));
  final offset = block.add(Load(.i32, table, index: at));
  final callee = block.add(PtrAdd(table, offset));
  final ten = block.add(ConstInt(10));
  return block.add(CallIndirect(callee, _unary, [ten]));
});

LirFunction _adding(String name, int amount) =>
    function(name, [.i64], .i64, (block, p) {
      return block.add(IntBinary(.add, p[0], block.add(ConstInt(amount))));
    });

LirModule _module(List<LirTable> tables, {List<LirData> data = const []}) =>
    LirModule(
      functions: [_adding('one', 1), _adding('two', 2), _caller()],
      tables: tables,
      data: data,
    );

void main() {
  test('entries are found relative to the table', () {
    final interpreter = LirInterpreter(
      _module([
        LirTable('t', ['two', 'one', 'two']),
      ]),
    );
    expect(interpreter.call('call', [0]), 12);
    expect(interpreter.call('call', [1]), 11);
    expect(interpreter.call('call', [2]), 12);
    expect(() => interpreter.call('call', [3]), throwsA(isA<LirFault>()));
  });

  test('a table cannot be written', () {
    final module = LirModule(
      functions: [
        function('f', [], null, (block, _) {
          final table = block.add(SymbolAddress('t'));
          block.add(Store(.i32, table, block.add(ConstInt(0))));
          return null;
        }),
      ],
      tables: [
        LirTable('t', ['f']),
      ],
    );
    expect(() => LirInterpreter(module).call('f'), throwsA(isA<LirFault>()));
  });

  group('rejects', () {
    void rejects(String message, LirModule Function() build) =>
        test(message, () {
          expect(
            () => verifyModule(build()),
            throwsA(
              isA<LirError>().having(
                (e) => e.message,
                'message',
                contains(message),
              ),
            ),
          );
        });

    rejects('Duplicate symbol: one', () => _module([LirTable('one', [])]));
    rejects('t: unknown function missing', () {
      return _module([
        LirTable('t', ['missing']),
      ]);
    });
    rejects('t: unknown function d', () {
      return _module(
        [
          LirTable('t', ['d']),
        ],
        data: [LirData('d', [])],
      );
    });
  });

  test('prints its functions', () {
    final text = printModule(
      _module([
        LirTable('t', ['two', 'one']),
      ]),
    );
    expect(text, startsWith('table t: two, one\n'));
  });
}
