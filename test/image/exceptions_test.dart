@TestOn('mac-os')
@Tags(['native'])
library;

import 'package:dartc/lir.dart';
import 'package:test/test.dart';

import '../lir/support.dart';
import 'agree.dart';
import 'support.dart';
import 'unwind.dart';

final _unary = LirSignature([.i64], .i64);

/// Throws an object holding its argument, and another, unless that is 0.
final LirFunction _raise = () {
  final entry = LirBlock([.i64]), bad = LirBlock(), fine = LirBlock();
  final n = entry.parameters.single;
  entry.end(Branch(n, LirEdge(bad), LirEdge(fine)));
  final size = bad.add(ConstInt(16));
  final exception = bad.add(Alloc(size)), trace = bad.add(Alloc(size));
  bad
    ..add(Store(.i64, exception, n, offset: 8))
    ..add(Store(.i64, trace, bad.add(ConstInt(1000)), offset: 8))
    ..end(Throw(exception, trace));
  fine.end(Return(fine.add(ConstInt(5))));
  return LirFunction('raise', _unary, [entry, bad, fine]);
}();

LirValue _sum(LirBlock block, Iterable<LirValue> values) =>
    values.reduce((a, b) => block.add(IntBinary(.add, a, b)));

LirValue _content(LirBlock block, LirValue object) =>
    block.add(Load(.i64, object, offset: 8));

/// Destroys every register that calls preserve, then throws.
LirFunction _clobber() => function('clobber', [.i64], .i64, (block, p) {
  final words = [
    for (var i = 0; i < 20; i++)
      block.add(IntBinary(.mul, p[0], block.add(ConstInt(i + 100)))),
  ];
  final floats = [
    for (final word in words) block.add(Convert(.intToFloat, word)),
  ];
  final call = block.add(Call('raise', _unary, [p[0]]));
  return _sum(block, [
    call,
    ...words,
    for (final float in floats) block.add(Convert(.floatToInt, float)),
  ]);
});

void main() {
  Future<void> check(List<LirFunction> functions, List<Case> cases) =>
      agree([throwFunction, _raise, ...functions], cases);

  List<Case> cases(String name, List<int> arguments) => [
    for (final n in arguments) (function: name, arguments: [n]),
  ];

  test('an exception and its trace reach the edge for throws', () async {
    final caught = catching('f', _raise, (block, p) {
      return _sum(block, [_content(block, p[0]), _content(block, p[1])]);
    });
    await check([caught], cases('f', [0, 1, 7, -3]));
  }, skip: skipExecution);

  test('a frame resumes with what it is given', () async {
    final caught = catching('f', _raise, (block, p) {
      final ten = block.add(ConstInt(10));
      final trace = block.add(IntBinary(.mul, _content(block, p[1]), ten));
      return block.add(IntBinary(.add, _content(block, p[0]), trace));
    });
    final module = program(
      [swappingThrowFunction, _raise, caught],
      cases('f', [3]),
      [1030],
    );
    expect(await execute(module), 0);
  }, skip: skipExecution);

  test('functions between are left', () async {
    final functions = [_clobber()];
    var below = functions.single;
    for (var i = 0; i < 4; i++) {
      final target = below.name;
      below = function('g$i', [.i64], .i64, (block, p) {
        final call = block.add(Call(target, _unary, p));
        return block.add(IntBinary(.add, call, p[0]));
      });
      functions.add(below);
    }
    final caught = catching('f', below, (block, p) => _content(block, p[0]));
    await check([...functions, caught], cases('f', [0, 1, 7, -3]));
  }, skip: skipExecution);

  test('values of every kind survive a throw', () async {
    final entry = LirBlock([.i64]), normal = LirBlock([.i64, .i64]);
    final handler = LirBlock([.ref, .ref, .f64]);
    final n = entry.parameters.single;
    final words = [
      for (var i = 0; i < 30; i++)
        entry.add(IntBinary(.xor, n, entry.add(ConstInt(i * 77)))),
    ];
    final floats = [
      for (final word in words) entry.add(Convert(.intToFloat, word)),
    ];
    final object = entry.add(Alloc(entry.add(ConstInt(16))));
    entry
      ..add(Store(.i64, object, words[3], offset: 8))
      ..end(
        Invoke(
          Call('clobber', _unary, [n]),
          LirEdge(normal, [words[5]]),
          LirEdge(handler, [floats[6]]),
        ),
      );
    void end(LirBlock block, List<LirValue> extra) => block.end(
      Return(
        _sum(block, [
          ...extra,
          ...words,
          for (final float in floats)
            block.add(
              Convert(
                .floatToInt,
                block.add(FloatBinary(.mul, float, block.add(ConstFloat(3)))),
              ),
            ),
          _content(block, object),
        ]),
      ),
    );
    end(normal, normal.parameters);
    end(handler, [
      _content(handler, handler.parameters[0]),
      _content(handler, handler.parameters[1]),
      handler.add(Convert(.floatToInt, handler.parameters[2])),
    ]);
    final f = LirFunction('f', _unary, [entry, normal, handler]);
    await check([_clobber(), f], cases('f', [0, 1, 7, -3]));
  }, skip: skipExecution);

  test('what the caller keeps in registers survives a caught throw', () async {
    final caught = catching('f', _clobber(), (b, p) => _content(b, p[0]));
    final outer = function('g', [.i64], .i64, (block, p) {
      final words = [
        for (var i = 0; i < 8; i++)
          block.add(IntBinary(.add, p[0], block.add(ConstInt(i * i)))),
      ];
      final floats = [
        for (final word in words) block.add(Convert(.intToFloat, word)),
      ];
      final call = block.add(Call('f', _unary, p));
      return _sum(block, [
        call,
        ...words,
        for (final float in floats) block.add(Convert(.floatToInt, float)),
      ]);
    });
    await check([_clobber(), caught, outer], cases('g', [0, 1, 7, -3]));
  }, skip: skipExecution);

  test('the innermost handler catches, and may throw again', () async {
    final inner = LirBlock([.i64]), normal = LirBlock([.i64]);
    final handler = LirBlock([.ref, .ref]);
    inner.end(
      Invoke(
        Call('raise', _unary, inner.parameters),
        LirEdge(normal),
        LirEdge(handler),
      ),
    );
    normal.end(Return(normal.parameters.single));
    final [exception, trace] = handler.parameters;
    final n = _content(handler, exception);
    handler.add(
      Store(
        .i64,
        exception,
        handler.add(IntBinary(.add, n, handler.add(ConstInt(10)))),
        offset: 8,
      ),
    );
    handler.end(Throw(exception, trace));
    final f = LirFunction('f', _unary, [inner, normal, handler]);
    final outer = catching('g', f, (b, p) => _content(b, p[0]));
    await check([f, outer], cases('g', [0, 1, 7]));
  }, skip: skipExecution);

  test('a loop catches again and again', () async {
    final entry = LirBlock([.i64]);
    final loop = LirBlock([.i64, .i64]), normal = LirBlock([.i64]);
    final handler = LirBlock([.ref, .ref]), done = LirBlock();
    final next = LirBlock([.i64]);
    entry.end(
      Jump(LirEdge(loop, [entry.parameters.single, entry.add(ConstInt(0))])),
    );
    final [n, sum] = loop.parameters;
    final odd = loop.add(IntBinary(.and, n, loop.add(ConstInt(1))));
    loop.end(
      Invoke(Call('raise', _unary, [odd]), LirEdge(normal), LirEdge(handler)),
    );
    normal.end(Jump(LirEdge(next, normal.parameters)));
    handler.end(
      Jump(LirEdge(next, [_content(handler, handler.parameters[1])])),
    );
    final total = next.add(IntBinary(.add, sum, next.parameters.single));
    final rest = next.add(IntBinary(.sub, n, next.add(ConstInt(1))));
    next.end(Branch(rest, LirEdge(loop, [rest, total]), LirEdge(done)));
    done.end(Return(total));
    final f = LirFunction('f', _unary, [
      entry,
      loop,
      normal,
      handler,
      next,
      done,
    ]);
    await check([f], cases('f', [1, 2, 9, 10000]));
  }, skip: skipExecution);

  test('calls with stack arguments, indirect calls and allocations', () async {
    final types = List.filled(14, LirType.i64);
    final many = function('many', types, .i64, (block, p) {
      final call = block.add(Call('raise', _unary, [p[13]]));
      return _sum(block, [call, ...p]);
    });
    final entry = LirBlock([.i64]);
    final a = LirBlock([.i64]), b = LirBlock([.i64]), c = LirBlock([.ref]);
    final handler = LirBlock([.ref, .ref, .i64]);
    final n = entry.parameters.single;
    final zero = entry.add(ConstInt(0)), two = entry.add(ConstInt(2));
    LirEdge thrown(LirValue step) => LirEdge(handler, [step]);
    final first = entry.add(Compare(.eq, n, entry.add(ConstInt(1))));
    entry.end(
      Invoke(
        Call('many', many.signature, [...List.filled(13, n), first]),
        LirEdge(a),
        thrown(zero),
      ),
    );
    final second = a.add(Compare(.eq, n, two));
    a.end(
      Invoke(
        CallIndirect(a.add(SymbolAddress('raise')), _unary, [second]),
        LirEdge(b),
        thrown(two),
      ),
    );
    b.end(Invoke(Alloc(b.add(ConstInt(24))), LirEdge(c), thrown(zero)));
    final object = c.parameters.single;
    c
      ..add(Store(.i64, object, n, offset: 16))
      ..end(
        Return(
          _sum(c, [
            c.add(Load(.i64, object, offset: 16)),
            a.parameters.single,
            b.parameters.single,
          ]),
        ),
      );
    handler.end(
      Return(
        _sum(handler, [
          handler.parameters[2],
          _content(handler, handler.parameters[0]),
          n,
        ]),
      ),
    );
    final f = LirFunction('f', _unary, [entry, a, b, c, handler]);
    await check([many, f], cases('f', [0, 1, 2, 3]));
  }, skip: skipExecution);

  group('the stack', () {
    /// Recurs [depth] times and reports -1 if that overflows the stack, which
    /// may reach [bytes] below the frame of `main`.
    LirModule recursing(int depth, int bytes, {int spills = 0}) {
      final entry = LirBlock([.i64]), more = LirBlock(), done = LirBlock();
      final n = entry.parameters.single;
      entry.end(Branch(n, LirEdge(more), LirEdge(done)));
      // Many values alive across the call make a large frame.
      final kept = [
        for (var i = 0; i < spills; i++)
          more.add(IntBinary(.add, n, more.add(ConstInt(i)))),
      ];
      final rest = more.add(IntBinary(.sub, n, more.add(ConstInt(1))));
      final found = more.add(Call('f', _unary, [rest]));
      more.end(Return(_sum(more, [found, ...kept])));
      done.end(Return(done.add(ConstInt(1))));
      final f = LirFunction('f', _unary, [
        entry,
        more,
        done,
      ], checksStack: true);
      final overflow = LirBlock();
      final none = overflow.add(ConstNull());
      overflow.end(Throw(none, none));
      final start = LirBlock(),
          ok = LirBlock([.i64]),
          bad = LirBlock([.ref, .ref]);
      final frame = start.add(FrameAddress());
      final limit = start.add(
        IntBinary(.sub, frame, start.add(ConstInt(bytes))),
      );
      start
        ..add(Store(.i64, start.add(StaticObject(stackLimitSymbol)), limit))
        ..end(
          Invoke(
            Call('f', _unary, [start.add(ConstInt(depth))]),
            LirEdge(ok),
            LirEdge(bad),
          ),
        );
      ok.end(Return(ok.add(ConstInt(0))));
      final isNull = bad.add(
        Compare(.eq, bad.parameters[0], bad.add(ConstNull())),
      );
      bad.end(Return(isNull));
      return LirModule(
        functions: [
          f,
          throwFunction,
          LirFunction(stackOverflowSymbol, LirSignature([]), [overflow]),
          LirFunction('main', LirSignature([], .i64), [start, ok, bad]),
        ],
        statics: [
          LirStatic(stackLimitSymbol, List.filled(8, 0), writable: true),
        ],
      );
    }

    test('overflows where its limit is', () async {
      expect(await execute(recursing(100, 100 << 10)), 0);
      expect(await execute(recursing(100000, 100 << 10)), 1);
      // The limit, not the guard page, decides.
      expect(await execute(recursing(1000, 64000)), 0);
      expect(await execute(recursing(1000, 16000)), 1);
    }, skip: skipExecution);

    test('is checked for the whole frame', () async {
      // A single frame of 800 KB, whose function calls nothing.
      expect(await execute(recursing(0, 700 << 10, spills: 100000)), 1);
      expect(await execute(recursing(0, 1700 << 10, spills: 100000)), 0);
      expect(await execute(recursing(1, 700 << 10, spills: 100000)), 1);
      expect(await execute(recursing(1, 1700 << 10, spills: 100000)), 0);
    }, skip: skipExecution);
  });
}
