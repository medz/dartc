import 'dart:typed_data';

import 'package:dartc/lir.dart';
import 'package:test/test.dart';

import 'support.dart';

const _min = -0x8000000000000000, _max = 0x7fffffffffffffff;

void main() {
  final fault = throwsA(isA<LirFault>());

  group('integers', () {
    int run(IntOp op, int a, int b) =>
        evaluate([.i64, .i64], .i64, (p) => IntBinary(op, p[0], p[1]), [a, b])
            as int;

    test('arithmetic wraps and truncates', () {
      expect(run(.add, _max, 1), _min);
      expect(run(.sub, _min, 1), _max);
      expect(run(.mul, _max, 2), -2);
      expect(run(.div, -7, 2), -3);
      expect(run(.rem, -7, 2), -1);
      expect(run(.div, _min, -1), _min);
      expect(run(.rem, _min, -1), 0);
      expect(run(.and, 12, 10), 8);
      expect(run(.or, 12, 10), 14);
      expect(run(.xor, 12, 10), 6);
      expect(run(.shl, 1, 63), _min);
      expect(run(.sar, -5, 1), -3);
      expect(run(.shr, -1, 1), _max);
    });

    test('broken preconditions fault', () {
      expect(() => run(.div, 1, 0), fault);
      expect(() => run(.rem, 1, 0), fault);
      for (final op in [IntOp.shl, IntOp.sar, IntOp.shr]) {
        expect(() => run(op, 1, 64), fault);
        expect(() => run(op, 1, -1), fault);
      }
    });
  });

  test('floats', () {
    Object? binary(FloatOp op, double a, double b) => evaluate(
      [.f64, .f64],
      .f64,
      (p) => FloatBinary(op, p[0], p[1]),
      [a, b],
    );
    Object? unary(FloatUnaryOp op, double a) =>
        evaluate([.f64], .f64, (p) => FloatUnary(op, p[0]), [a]);
    expect(binary(.add, 1.5, 2), 3.5);
    expect(binary(.sub, 1.5, 2), -0.5);
    expect(binary(.mul, 1.5, 2), 3.0);
    expect(binary(.div, 1, 0), double.infinity);
    expect((unary(.neg, 0) as double).isNegative, isTrue);
    expect(unary(.sqrt, 9), 3.0);
    expect(unary(.sqrt, -1), isNaN);
  });

  test('comparisons', () {
    bool run(LirType type, Relation relation, Object? a, Object? b) =>
        evaluate(
          [type, type],
          .i64,
          (p) => Compare(relation, p[0], p[1]),
          [a, b],
        ) ==
        1;
    // Outcomes of -1 against 1 for each relation in declaration order.
    const expected = {
      Relation.eq: false,
      Relation.ne: true,
      Relation.lt: true,
      Relation.le: true,
      Relation.gt: false,
      Relation.ge: false,
      Relation.ult: false,
      Relation.ule: false,
      Relation.ugt: true,
      Relation.uge: true,
    };
    for (final relation in Relation.values) {
      expect(
        run(.i64, relation, -1, 1),
        expected[relation],
        reason: '$relation',
      );
      final reflexive = const {'eq', 'le', 'ge', 'ule', 'uge'};
      expect(run(.i64, relation, 7, 7), reflexive.contains(relation.name));
      if (!relation.isUnsigned) {
        expect(run(.f64, relation, -1.0, 1.0), expected[relation]);
        expect(run(.f64, relation, double.nan, double.nan), relation == .ne);
        expect(
          run(.f64, relation, 0.0, -0.0),
          reflexive.contains(relation.name),
        );
      }
    }
    final object = LirObject(0), other = LirObject(0);
    expect(run(.ref, .eq, object, object), isTrue);
    expect(run(.ref, .eq, object, other), isFalse);
    expect(run(.ref, .ne, object, null), isTrue);
    expect(run(.ref, .eq, null, null), isTrue);
    expect(run(.ptr, .eq, 4, 4), isTrue);
    expect(run(.ptr, .ne, 4, 4), isFalse);
  });

  test('conversions', () {
    Object? run(Conversion op, Object value) =>
        evaluate([op.from], op.to, (p) => Convert(op, p[0]), [value]);
    expect(run(.intToFloat, 3), 3.0);
    expect(run(.floatToInt, -3.9), -3);
    expect(run(.floatToInt, _min.toDouble()), _min);
    expect(run(.intBitsToFloat, 0x3ff0000000000000), 1.0);
    expect(run(.floatBitsToInt, -0.0), _min);
    expect(run(.intToPtr, 5), 5);
    expect(run(.ptrToInt, 5), 5);
    for (final bad in [double.nan, double.infinity, 9223372036854775808.0]) {
      expect(() => run(.floatToInt, bad), fault);
    }
  });

  test('constants', () {
    Object? run(LirType type, LirInstruction value) =>
        evaluate([], type, (_) => value, []);
    expect(run(.i64, ConstInt(_min)), _min);
    expect((run(.f64, ConstFloat(-0.0)) as double).isNegative, isTrue);
    expect(run(.ref, ConstNull()), isNull);
  });

  group('memory', () {
    test('stores keep the low bytes and loads extend them', () {
      const expected = {
        Width.i8: -2,
        Width.u8: 0xfe,
        Width.i16: -2,
        Width.u16: 0xfffe,
        Width.i32: -2,
        Width.u32: 0xfffffffe,
        Width.i64: -2,
      };
      for (final MapEntry(key: width, value: result) in expected.entries) {
        for (final managed in [true, false]) {
          final body = function('f', [.i64, .i64], .i64, (block, p) {
            final LirValue base = managed
                ? block.add(Alloc(block.add(ConstInt(32))))
                : block.add(
                    PtrAdd(
                      block.add(SymbolAddress('data')),
                      block.add(ConstInt(8)),
                    ),
                  );
            block.add(Store(width, base, p[0], offset: 8, index: p[1]));
            return block.add(Load(width, base, offset: 8, index: p[1]));
          });
          final module = LirModule(
            functions: [body],
            data: [LirData('data', List.filled(64, 0), writable: true)],
          );
          expect(LirInterpreter(module).call('f', [-2, 8]), result);
        }
      }
    });

    test('floats, addresses and references round trip', () {
      Object? run(LirType type, Width width, Object? value) => LirInterpreter(
        LirModule(
          functions: [
            function('f', [type], type, (block, p) {
              final object = block.add(Alloc(block.add(ConstInt(16))));
              block.add(Store(width, object, p[0], offset: 8));
              return block.add(Load(width, object, offset: 8));
            }),
          ],
        ),
      ).call('f', [value]);
      expect(run(.f64, .f64, 0.1), 0.1);
      expect(run(.f64, .f32, 0.1), closeTo(0.1, 1e-7));
      expect(run(.f64, .f32, 0.1), isNot(0.1));
      expect(run(.ptr, .ptr, 0x1234), 0x1234);
      final object = LirObject(8);
      expect(run(.ref, .ref, object), same(object));
      expect(run(.ref, .ref, null), isNull);
    });

    test('new objects are zero', () {
      Object? run(LirType type, Width width) => LirInterpreter(
        LirModule(
          functions: [
            function('f', [], type, (block, _) {
              final object = block.add(Alloc(block.add(ConstInt(8))));
              return block.add(Load(width, object));
            }),
          ],
        ),
      ).call('f');
      expect(run(.i64, .i64), 0);
      expect(run(.ref, .ref), isNull);
    });

    test('invalid accesses fault', () {
      final memory = LirMemory();
      final object = LirObject(16);
      expect(() => memory.load(.i64, null, 0), fault);
      expect(() => memory.load(.i64, object, 9), fault);
      expect(() => memory.load(.i64, object, -1), fault);
      expect(() => memory.store(.i64, object, 9, 1), fault);
      expect(() => memory.store(.ref, object, 16, object), fault);
      expect(() => memory.load(.i64, 1, 0), fault);
      expect(() => memory.load(.ref, object, 4), fault);
      memory.store(.ref, object, 8, object);
      expect(() => memory.load(.i8, object, 15), fault);
      expect(() => memory.store(.i8, object, 8, 1), fault);
      memory.store(.ref, object, 8, null);
      memory.store(.i8, object, 8, 2);
      expect(() => memory.load(.ref, object, 8), fault);
      expect(() => memory.store(.ref, object, 8, object), fault);
      expect(() => memory.load(.i64, const LirNumber(1), 0), fault);
      final native = memory.map(Uint8List(8));
      expect(() => memory.load(.i64, native, 1), fault);
      expect(() => memory.load(.ref, native, 0), fault);
      expect(() => memory.store(.ref, native, 0, null), fault);
      final constant = memory.map(Uint8List(8), writable: false);
      expect(memory.load(.i64, constant, 0), 0);
      expect(() => memory.store(.i64, constant, 0, 1), fault);
    });

    test('odd numbers are references', () {
      final memory = LirMemory(), object = LirObject(16);
      memory.store(.i64, object, 8, -3);
      expect(memory.load(.ref, object, 8), const LirNumber(-3));
      memory.store(.ref, object, 8, object);
      expect(memory.load(.ref, object, 8), object);
      memory.store(.ref, object, 8, const LirNumber(7));
      expect(memory.load(.ref, object, 8), const LirNumber(7));
      expect(() => memory.load(.i64, object, 8), fault);
      memory.store(.ref, object, 8, null);
      expect(memory.load(.ref, object, 8), isNull);
    });

    test('host code reads native bytes', () {
      final memory = LirMemory();
      final bytes = Uint8List.sublistView(Uint8List.fromList([9, 1, 2, 3]), 1);
      expect(memory.read(memory.map(bytes) + 1, 2), [2, 3]);
    });

    test('allocation size is not negative', () {
      expect(() => evaluate([.i64], .ref, (p) => Alloc(p[0]), [-1]), fault);
    });
  });

  group('control flow', () {
    test('loops pass edge arguments in parallel', () {
      // Fibonacci swaps two block parameters on its back edge.
      final entry = LirBlock([.i64]);
      final loop = LirBlock([.i64, .i64, .i64]);
      final done = LirBlock([.i64]);
      final zero = entry.add(ConstInt(0)), one = entry.add(ConstInt(1));
      entry.end(Jump(LirEdge(loop, [entry.parameters[0], zero, one])));
      final [n, a, b] = loop.parameters;
      final next = loop.add(IntBinary(.add, a, b));
      final less = loop.add(IntBinary(.sub, n, one));
      loop.end(Branch(n, LirEdge(loop, [less, b, next]), LirEdge(done, [a])));
      done.end(Return(done.parameters.single));
      final module = LirModule(
        functions: [
          LirFunction('fib', LirSignature([.i64], .i64), [entry, loop, done]),
        ],
      );
      expect(LirInterpreter(module).call('fib', [0]), 0);
      expect(LirInterpreter(module).call('fib', [50]), 12586269025);
      expect(
        () => LirInterpreter(module, maxSteps: 20).call('fib', [50]),
        fault,
      );
    });

    test('unreachable code faults', () {
      final block = LirBlock()..end(Unreachable());
      final module = LirModule(
        functions: [
          LirFunction('f', LirSignature([]), [block]),
        ],
      );
      expect(() => LirInterpreter(module).call('f'), fault);
    });
  });

  group('calls', () {
    final signature = LirSignature([.i64], .i64);
    final twice = function('twice', [.i64], .i64, (block, p) {
      return block.add(IntBinary(.add, p[0], p[0]));
    });

    test('direct, external and indirect', () {
      final module = LirModule(
        functions: [
          twice,
          function('f', [.i64], .i64, (block, p) {
            final direct = block.add(Call('twice', signature, p));
            final host = block.add(Call('host', signature, [direct]));
            final address = block.add(SymbolAddress('twice'));
            return block.add(CallIndirect(address, signature, [host]));
          }),
        ],
        externals: [LirExternal('host', signature)],
      );
      final interpreter = LirInterpreter(
        module,
        externals: {'host': (_, arguments) => (arguments.single as int) + 1},
      );
      expect(interpreter.call('f', [5]), 22);
      expect(() => LirInterpreter(module).call('f', [5]), fault);
      expect(() => interpreter.call('missing'), fault);
      expect(() => interpreter.call('f', []), fault);
    });

    test('indirect calls check their target', () {
      LirModule calling(LirSignature used, String symbol) => LirModule(
        functions: [
          twice,
          function('f', [], null, (block, _) {
            final address = block.add(SymbolAddress(symbol));
            final arguments = [
              for (final type in used.parameters)
                type == .f64
                    ? block.add(ConstFloat(0))
                    : block.add(ConstInt(0)),
            ];
            block.add(CallIndirect(address, used, arguments));
            return null;
          }),
        ],
        data: [
          LirData('data', [0]),
        ],
      );
      LirInterpreter(calling(signature, 'twice')).call('f');
      expect(
        () => LirInterpreter(calling(LirSignature([]), 'twice')).call('f'),
        fault,
      );
      // Same arity, so only the signature check can reject it.
      expect(
        () =>
            LirInterpreter(calling(LirSignature([.f64], .i64), 'twice'))
                .call('f'),
        fault,
      );
      expect(() => LirInterpreter(calling(signature, 'data')).call('f'), fault);
    });
  });

  group('exceptions', () {
    final thrower = LirBlock([.ref, .ref]);
    thrower.end(Throw(thrower.parameters[0], thrower.parameters[1]));
    final pair = LirSignature([.ref, .ref]);
    final raise = LirFunction('raise', pair, [thrower]);

    test('propagate through plain calls', () {
      final module = LirModule(
        functions: [
          raise,
          function('f', [.ref, .ref], null, (block, p) {
            block.add(Call('raise', pair, p));
            return null;
          }),
        ],
      );
      final exception = LirObject(0), trace = LirObject(0);
      expect(
        () => LirInterpreter(module).call('f', [exception, trace]),
        throwsA(
          isA<LirException>()
              .having((e) => e.exception, 'exception', same(exception))
              .having((e) => e.trace, 'trace', same(trace)),
        ),
      );
    });

    test('invoke chooses the edge by outcome', () {
      final entry = LirBlock([.ref, .ref, .i64]);
      final normal = LirBlock([.i64, .i64]);
      final handler = LirBlock([.ref, .ref, .i64]);
      final [exception, trace, number] = entry.parameters;
      final maybe = LirSignature([.ref, .ref, .i64], .i64);
      entry.end(
        Invoke(
          Call('maybe', maybe, [exception, trace, number]),
          LirEdge(normal, [number]),
          LirEdge(handler, [number]),
        ),
      );
      normal.end(
        Return(
          normal.add(
            IntBinary(.add, normal.parameters[0], normal.parameters[1]),
          ),
        ),
      );
      final same = handler.add(Compare(.eq, handler.parameters[0], exception));
      handler.end(
        Return(handler.add(IntBinary(.sub, same, handler.parameters[2]))),
      );
      final first = LirBlock([.ref, .ref, .i64]);
      final fine = LirBlock(), bad = LirBlock();
      first.end(Branch(first.parameters[2], LirEdge(fine), LirEdge(bad)));
      fine.end(Return(fine.add(ConstInt(100))));
      bad.end(Throw(first.parameters[0], first.parameters[1]));
      final module = LirModule(
        functions: [
          LirFunction('f', maybe, [entry, normal, handler]),
          LirFunction('maybe', maybe, [first, fine, bad]),
        ],
      );
      final objects = [LirObject(0), LirObject(0)];
      expect(LirInterpreter(module).call('f', [...objects, 7]), 107);
      expect(LirInterpreter(module).call('f', [...objects, 0]), 1);
    });

    test('faults are not Dart exceptions', () {
      final entry = LirBlock([.i64]), normal = LirBlock([.ref]);
      final handler = LirBlock([.ref, .ref]);
      entry.end(
        Invoke(Alloc(entry.parameters[0]), LirEdge(normal), LirEdge(handler)),
      );
      normal.end(Return());
      handler.end(Return());
      final module = LirModule(
        functions: [
          LirFunction('f', LirSignature([.i64]), [entry, normal, handler]),
        ],
      );
      LirInterpreter(module).call('f', [8]);
      expect(() => LirInterpreter(module).call('f', [-1]), fault);
    });
  });
}
