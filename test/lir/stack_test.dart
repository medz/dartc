import 'package:dartc/lir.dart';
import 'package:test/test.dart';

import 'support.dart';

final _none = LirSignature([]);
final _unary = LirSignature([.i64], .i64);

/// Calls itself as often as its argument says, then returns it.
LirFunction _recursive({bool checksStack = true}) {
  final entry = LirBlock([.i64]), more = LirBlock(), done = LirBlock();
  final n = entry.parameters.single;
  entry.end(Branch(n, LirEdge(more), LirEdge(done)));
  final rest = more.add(IntBinary(.sub, n, more.add(ConstInt(1))));
  final found = more.add(Call('f', _unary, [rest]));
  more.end(Return(more.add(IntBinary(.add, found, more.add(ConstInt(1))))));
  done.end(Return(n));
  return LirFunction('f', _unary, [
    entry,
    more,
    done,
  ], checksStack: checksStack);
}

/// Throws nulls.
final _overflow = () {
  final block = LirBlock();
  final none = block.add(ConstNull());
  block.end(Throw(none, none));
  return LirFunction(stackOverflowSymbol, _none, [block]);
}();

LirModule _module(
  LirFunction f, {
  LirFunction? overflow,
  List<LirStatic>? statics,
}) => LirModule(
  functions: [f, overflow ?? _overflow],
  statics:
      statics ??
      [LirStatic(stackLimitSymbol, List.filled(8, 0), writable: true)],
);

void main() {
  test('deep calls overflow the stack', () {
    final interpreter = LirInterpreter(_module(_recursive()), maxDepth: 100);
    expect(interpreter.call('f', [90]), 90);
    expect(() => interpreter.call('f', [110]), throwsA(isA<LirException>()));
    // Unwinding gives the stack back.
    expect(interpreter.call('f', [90]), 90);
  });

  test('only functions that check it overflow the stack', () {
    final module = _module(_recursive(checksStack: false));
    expect(LirInterpreter(module, maxDepth: 100).call('f', [110]), 110);
  });

  test('an overflow is caught like other exceptions', () {
    final entry = LirBlock([.i64]), normal = LirBlock([.i64]);
    final handler = LirBlock([.ref, .ref]);
    entry.end(
      Invoke(
        Call('f', _unary, entry.parameters),
        LirEdge(normal),
        LirEdge(handler),
      ),
    );
    normal.end(Return(normal.parameters.single));
    handler.end(Return(handler.add(ConstInt(-1))));
    final module = LirModule(
      functions: [
        LirFunction('g', _unary, [entry, normal, handler]),
        _recursive(),
        _overflow,
      ],
      statics: [LirStatic(stackLimitSymbol, List.filled(8, 0), writable: true)],
    );
    final interpreter = LirInterpreter(module, maxDepth: 100);
    expect(interpreter.call('g', [110]), -1);
    expect(interpreter.call('g', [10]), 10);
  });

  test('resuming a frame is not interpreted', () {
    final module = LirModule(
      functions: [
        function('f', [.i64, .ref], null, (block, p) {
          block.add(Resume(p[0], p[0], p[1], p[1]));
          return null;
        }),
      ],
    );
    expect(
      () => LirInterpreter(module).call('f', [0, null]),
      throwsA(isA<LirFault>()),
    );
    expect(printModule(module), contains('  resume v0, v0, v1, v1\n'));
  });

  group('rejects', () {
    void rejects(String message, LirModule module) => test(message, () {
      expect(
        () => verifyModule(module),
        throwsA(isA<LirError>().having((e) => e.message, 'message', message)),
      );
    });

    rejects(
      'f: nothing to call when the stack overflows',
      LirModule(
        functions: [_recursive()],
        statics: [
          LirStatic(stackLimitSymbol, List.filled(8, 0), writable: true),
        ],
      ),
    );
    rejects(
      'f: nothing to call when the stack overflows',
      _module(
        _recursive(),
        overflow: function(stackOverflowSymbol, [.i64], null, (_, _) => null),
      ),
    );
    for (final statics in [
      <LirStatic>[],
      [LirStatic(stackLimitSymbol, List.filled(8, 0))],
      [LirStatic(stackLimitSymbol, List.filled(7, 0), writable: true)],
    ]) {
      rejects(
        'f: no stack limit to check',
        _module(_recursive(), statics: statics),
      );
    }
    LirModule resuming(int wrong) => LirModule(
      functions: [
        function('f', [.i64, .ref, .f64], null, (block, p) {
          final inputs = [p[0], p[0], p[1], p[1]];
          inputs[wrong] = p[2];
          block.add(Resume(inputs[0], inputs[1], inputs[2], inputs[3]));
          return null;
        }),
      ],
    );
    for (final (i, what) in [
      'frame: expected i64',
      'code: expected i64',
      'exception: expected ref',
      'stack trace: expected ref',
    ].indexed) {
      rejects('f: $what, found f64', resuming(i));
    }
  });
}
