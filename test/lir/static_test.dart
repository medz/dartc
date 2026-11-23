import 'package:dartc/lir.dart';
import 'package:test/test.dart';

import 'support.dart';

LirModule _module(
  LirFunction f, {
  List<LirStatic> statics = const [],
  List<LirData> data = const [],
}) => LirModule(functions: [f], statics: statics, data: data);

/// Little-endian words.
List<int> _words(List<int> values) => [
  for (final value in values)
    for (var i = 0; i < 8; i++) value >> i * 8 & 0xff,
];

void main() {
  final fault = throwsA(isA<LirFault>());

  test('hold bytes and references to each other', () {
    final f = function('f', [], .i64, (block, _) {
      final a = block.add(StaticObject('a'));
      final b = block.add(Load(.ref, a, offset: 16));
      final again = block.add(StaticObject('b'));
      final same = block.add(Compare(.eq, b, again));
      final back = block.add(Load(.ref, b, offset: 8));
      final value = block.add(Load(.i64, back, offset: 8));
      return block.add(IntBinary(.add, value, same));
    });
    final interpreter = LirInterpreter(
      _module(
        f,
        statics: [
          LirStatic('a', _words([0, 40, 0]), references: {16: 'b'}),
          LirStatic('b', _words([0, 0]), references: {8: 'a'}),
        ],
      ),
    );
    expect(interpreter.call('f'), 41);
  });

  test('only writable ones change, and keep their changes', () {
    LirInterpreter storing(bool writable) => LirInterpreter(
      _module(
        function('f', [], .i64, (block, _) {
          final object = block.add(StaticObject('a'));
          final old = block.add(Load(.i64, object, offset: 8));
          final one = block.add(ConstInt(1));
          final next = block.add(IntBinary(.add, old, one));
          block.add(Store(.i64, object, next, offset: 8));
          block.add(Store(.ref, object, object, offset: 16));
          return next;
        }),
        statics: [
          LirStatic('a', _words([0, 5, 0]), writable: writable),
        ],
      ),
    );
    final writable = storing(true);
    expect(writable.call('f'), 6);
    expect(writable.call('f'), 7);
    expect(() => storing(false).call('f'), fault);
  });

  test('a reference cannot be read as bytes', () {
    final module = _module(
      function('f', [], .i64, (block, _) {
        return block.add(Load(.i64, block.add(StaticObject('a')), offset: 8));
      }),
      statics: [
        LirStatic('a', _words([0, 0]), references: {8: 'a'}),
      ],
    );
    expect(() => LirInterpreter(module).call('f'), fault);
  });

  test('runtime operations are not interpreted', () {
    for (final LirInstruction instruction in [FrameAddress()]) {
      final module = _module(
        function('f', [], .i64, (block, _) => block.add(instruction)),
      );
      expect(() => LirInterpreter(module).call('f'), fault);
    }
    final module = _module(
      function('f', [.i64], .ref, (block, p) {
        return block.add(Convert(.intToRef, p[0]));
      }),
    );
    expect(() => LirInterpreter(module).call('f', [0]), fault);
  });

  group('rejects', () {
    final nothing = function('f', [], null, (_, _) => null);
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

    rejects('Duplicate symbol: f', () {
      return _module(
        nothing,
        statics: [
          LirStatic('f', _words([0])),
        ],
      );
    });
    rejects('a: unknown object b', () {
      return _module(
        nothing,
        statics: [
          LirStatic('a', _words([0, 0]), references: {8: 'b'}),
        ],
      );
    });
    rejects('a: unknown object d', () {
      return _module(
        nothing,
        statics: [
          LirStatic('a', _words([0, 0]), references: {8: 'd'}),
        ],
        data: [LirData('d', [])],
      );
    });
    for (final offset in [4, 9, 16, -8]) {
      rejects('a: no reference fits at $offset', () {
        return _module(
          nothing,
          statics: [
            LirStatic('a', _words([0, 0]), references: {offset: 'a'}),
          ],
        );
      });
    }
    rejects('a: bytes where a reference belongs', () {
      return _module(
        nothing,
        statics: [
          LirStatic('a', _words([0, 1]), references: {8: 'a'}),
        ],
      );
    });
    rejects('unknown object d', () {
      return _module(
        function('f', [], null, (block, _) {
          block.add(StaticObject('d'));
          return null;
        }),
        data: [LirData('d', [])],
      );
    });
  });

  test('the symbols of emitted code are always known', () {
    verifyModule(
      _module(
        function('f', [], null, (block, _) {
          block
            ..add(SymbolAddress(textSymbol))
            ..add(SymbolAddress(stackMapSymbol));
          return null;
        }),
      ),
    );
  });

  test('prints', () {
    final text = printModule(
      _module(
        function('f', [.i64], null, (block, p) {
          block
            ..add(StaticObject('a'))
            ..add(FrameAddress())
            ..add(Convert(.intToRef, p[0]));
          return null;
        }),
        statics: [
          LirStatic('a', _words([0, 0]), references: {8: 'a'}, writable: true),
        ],
      ),
    );
    expect(text, '''
object a: 16 bytes, 8: a, writable
func f(i64) {
b0(v0: i64):
  v1 = object a
  v2 = frame
  v3 = intToRef v0
  return
}''');
  });
}
