import 'package:dartc/lir.dart';
import 'package:test/test.dart';

import 'support.dart';

final _unit = LirSignature([]);

LirModule _module(List<LirBlock> blocks, [LirSignature? signature]) =>
    LirModule(
      functions: [LirFunction('f', signature ?? _unit, blocks)],
      data: [
        LirData('data', [0]),
      ],
    );

/// A module whose single block holds what [build] adds.
LirModule _body(
  List<LirType> parameters,
  void Function(LirBlock block, List<LirParameter> p) build,
) => LirModule(
  functions: [
    function('f', parameters, null, (block, p) {
      build(block, p);
      return null;
    }),
    function('callee', [.i64], .i64, (_, p) => p[0]),
  ],
  data: [
    LirData('data', [0]),
  ],
);

void _rejects(String message, LirModule Function() build) {
  test('rejects: $message', () {
    expect(
      () => verifyModule(build()),
      throwsA(
        isA<LirError>().having((e) => e.message, 'message', contains(message)),
      ),
    );
  });
}

void main() {
  final one = LirSignature([.i64], .i64);

  test('accepts a well-formed module', () {
    verifyModule(
      _body([.i64, .ref], (block, p) {
        final result = block.add(Call('callee', one, [p[0]]));
        block.add(Store(.i64, p[1], result, offset: 8));
        block.add(SymbolAddress('data'));
      }),
    );
  });

  test('a block accepts one terminator and nothing after it', () {
    final block = LirBlock()..end(Return());
    expect(() => block.end(Return()), throwsStateError);
    expect(() => block.add(ConstInt(1)), throwsStateError);
  });

  group('structure', () {
    _rejects('Duplicate symbol', () {
      return LirModule(
        externals: [LirExternal('x', _unit)],
        data: [LirData('x', [])],
      );
    });
    _rejects('no blocks', () => _module([]));
    _rejects('a block is listed twice', () {
      final block = LirBlock()..end(Return());
      return _module([block, block]);
    });
    _rejects('entry parameters differ', () {
      return _module([
        LirBlock([.i64])..end(Return()),
      ]);
    });
    _rejects('no terminator', () => _module([LirBlock()]));
    _rejects('edge leaves the function', () {
      final other = LirBlock()..end(Return());
      return _module([LirBlock()..end(Jump(LirEdge(other)))]);
    });
    _rejects('edge enters the entry block', () {
      final block = LirBlock();
      block.end(Jump(LirEdge(block)));
      return _module([block]);
    });
    _rejects('unreachable block', () {
      return _module([LirBlock()..end(Return()), LirBlock()..end(Return())]);
    });
    _rejects('invoke shares one edge', () {
      final entry = LirBlock(), next = LirBlock([.ref, .ref])..end(Return());
      final edge = LirEdge(next);
      entry.end(Invoke(Alloc(entry.add(ConstInt(8))), edge, edge));
      return _module([entry, next]);
    });
  });

  group('definitions', () {
    _rejects('a value is defined twice', () {
      final constant = ConstInt(1);
      return _module([
        LirBlock()
          ..add(constant)
          ..add(constant)
          ..end(Return()),
      ]);
    });
    _rejects('a call is executed at two places', () {
      final entry = LirBlock();
      final normal = LirBlock([.ref])..end(Return());
      final handler = LirBlock([.ref, .ref])..end(Return());
      final call = Alloc(entry.add(ConstInt(8)));
      entry.add(call);
      entry.end(Invoke(call, LirEdge(normal), LirEdge(handler)));
      return _module([entry, normal, handler]);
    });
    _rejects('a call is executed at two places', () {
      final entry = LirBlock(), left = LirBlock(), right = LirBlock();
      final normal = LirBlock([.ref])..end(Return());
      final handler = LirBlock([.ref, .ref])..end(Return());
      final size = entry.add(ConstInt(8));
      entry.end(Branch(size, LirEdge(left), LirEdge(right)));
      final call = Alloc(size);
      for (final block in [left, right]) {
        block.end(Invoke(call, LirEdge(normal), LirEdge(handler)));
      }
      return _module([entry, left, right, normal, handler]);
    });
    _rejects('use of an undefined value', () {
      return _body([], (block, _) => block.add(Alloc(ConstInt(8))));
    });
    _rejects('use of an undefined value', () {
      // An invoked call's result exists only as the normal edge's parameter.
      final entry = LirBlock(), normal = LirBlock([.ref]);
      final handler = LirBlock([.ref, .ref])..end(Return());
      final call = Alloc(entry.add(ConstInt(8)));
      entry.end(Invoke(call, LirEdge(normal), LirEdge(handler)));
      normal.add(Load(.i64, call));
      normal.end(Return());
      return _module([entry, normal, handler]);
    });
    _rejects('use of an undefined value', () {
      // An operand of an invoked call.
      final entry = LirBlock(), normal = LirBlock([.ref])..end(Return());
      final handler = LirBlock([.ref, .ref])..end(Return());
      entry.end(Invoke(Alloc(ConstInt(8)), LirEdge(normal), LirEdge(handler)));
      return _module([entry, normal, handler]);
    });
    _rejects('use of an undefined value', () {
      // An edge argument.
      final entry = LirBlock(), next = LirBlock([.i64])..end(Return());
      entry.end(Jump(LirEdge(next, [ConstInt(1)])));
      return _module([entry, next]);
    });
    _rejects('without a result', () {
      return _body([.ref, .i64], (block, p) {
        final store = block.add(Store(.i64, p[0], p[1]));
        block.add(Alloc(store));
      });
    });
    _rejects('does not dominate', () {
      // The use comes before its definition in one block.
      final size = ConstInt(8);
      return _body([], (block, _) {
        block.add(Alloc(size));
        block.add(size);
      });
    });
    _rejects('does not dominate', () {
      // Defined on one side of a branch, used after the join.
      final entry = LirBlock([.i64]);
      final left = LirBlock(), right = LirBlock(), join = LirBlock();
      entry.end(Branch(entry.parameters[0], LirEdge(left), LirEdge(right)));
      final value = left.add(ConstInt(1));
      left.end(Jump(LirEdge(join)));
      right.end(Jump(LirEdge(join)));
      join.end(Return(value));
      return _module([entry, left, right, join], one);
    });
    test('accepts a definition above a loop and its exit', () {
      final entry = LirBlock([.i64]), loop = LirBlock(), exit = LirBlock();
      final value = entry.add(ConstInt(1));
      entry.end(Jump(LirEdge(loop)));
      final inner = loop.add(IntBinary(.add, value, entry.parameters[0]));
      loop.end(Branch(inner, LirEdge(loop), LirEdge(exit)));
      exit.end(Return(inner));
      verifyModule(_module([entry, loop, exit], one));
    });
  });

  group('operand types', () {
    void instruction(
      String message,
      LirInstruction Function(LirValue i, LirValue f, LirValue r, LirValue p)
      build,
    ) => _rejects(message, () {
      return _body([.i64, .f64, .ref, .ptr], (block, v) {
        block.add(build(v[0], v[1], v[2], v[3]));
      });
    });

    instruction('unknown symbol', (_, _, _, _) => SymbolAddress('missing'));
    instruction('integer operand', (i, f, _, _) => IntBinary(.add, i, f));
    instruction('integer operand', (i, f, _, _) => IntBinary(.add, f, i));
    instruction('float operand', (i, f, _, _) => FloatBinary(.add, f, i));
    instruction('float operand', (i, f, _, _) => FloatBinary(.add, i, f));
    instruction('float operand', (i, _, _, _) => FloatUnary(.neg, i));
    instruction('compared value', (i, f, _, _) => Compare(.eq, i, f));
    instruction('f64 has no ult', (_, f, _, _) => Compare(.ult, f, f));
    instruction('ref has no lt', (_, _, r, _) => Compare(.lt, r, r));
    instruction('ptr has no lt', (_, _, _, p) => Compare(.lt, p, p));
    instruction('intToFloat', (_, f, _, _) => Convert(.intToFloat, f));
    instruction('ptrToInt', (_, _, r, _) => Convert(.ptrToInt, r));
    instruction('address: expected ptr', (i, _, r, _) => PtrAdd(r, i));
    instruction('address offset', (_, f, _, p) => PtrAdd(p, f));
    instruction('memory base is i64', (i, _, _, _) => Load(.i64, i));
    instruction('outside a managed', (_, _, _, p) => Load(.ref, p));
    instruction('outside a managed', (_, _, r, p) => Store(.ref, p, r));
    instruction('memory index', (_, f, r, _) => Load(.i64, r, index: f));
    instruction('stored value', (i, _, r, _) => Store(.f64, r, i));
    instruction('unknown callee', (_, _, _, _) => Call('missing', _unit, []));
    instruction('has signature', (_, _, _, _) => Call('callee', _unit, []));
    instruction('0 arguments for 1', (_, _, _, _) => Call('callee', one, []));
    instruction('call to callee', (_, f, _, _) => Call('callee', one, [f]));
    instruction('callee address', (i, _, _, _) => CallIndirect(i, _unit, []));
    instruction('indirect call', (_, f, _, p) => CallIndirect(p, one, [f]));
    instruction('allocation size', (_, f, _, _) => Alloc(f));
  });

  group('terminators', () {
    _rejects('branch condition', () {
      final entry = LirBlock(), left = LirBlock()..end(Return());
      final right = LirBlock()..end(Return());
      final value = entry.add(ConstFloat(1));
      entry.end(Branch(value, LirEdge(left), LirEdge(right)));
      return _module([entry, left, right]);
    });
    _rejects(
      'returns null',
      () => _module([
        LirBlock([.i64])..end(Return()),
      ], one),
    );
    _rejects('returns f64', () {
      final entry = LirBlock([.i64]);
      entry.end(Return(entry.add(ConstFloat(1))));
      return _module([entry], one);
    });
    _rejects('exception: expected ref', () {
      final entry = LirBlock();
      final trace = entry.add(ConstNull()), bad = entry.add(ConstInt(1));
      entry.end(Throw(bad, trace));
      return _module([entry]);
    });
    _rejects('stack trace: expected ref', () {
      final entry = LirBlock();
      final exception = entry.add(ConstNull()), bad = entry.add(ConstInt(1));
      entry.end(Throw(exception, bad));
      return _module([entry]);
    });
    _rejects('edge arguments', () {
      final entry = LirBlock(), next = LirBlock([.i64])..end(Return());
      entry.end(Jump(LirEdge(next)));
      return _module([entry, next]);
    });
    _rejects('edge arguments', () {
      final entry = LirBlock(), next = LirBlock([.i64])..end(Return());
      entry.end(Jump(LirEdge(next, [entry.add(ConstFloat(1))])));
      return _module([entry, next]);
    });
    _rejects('does not accept the call outcome', () {
      final entry = LirBlock(), normal = LirBlock()..end(Return());
      final handler = LirBlock([.ref, .ref])..end(Return());
      final size = entry.add(ConstInt(8));
      entry.end(Invoke(Alloc(size), LirEdge(normal), LirEdge(handler)));
      return _module([entry, normal, handler]);
    });
    _rejects('does not accept the call outcome', () {
      final entry = LirBlock(), normal = LirBlock([.ref])..end(Return());
      final handler = LirBlock([.ref, .i64])..end(Return());
      final size = entry.add(ConstInt(8));
      entry.end(Invoke(Alloc(size), LirEdge(normal), LirEdge(handler)));
      return _module([entry, normal, handler]);
    });
    _rejects('allocation size', () {
      final entry = LirBlock(), normal = LirBlock([.ref])..end(Return());
      final handler = LirBlock([.ref, .ref])..end(Return());
      final size = entry.add(ConstFloat(8));
      entry.end(Invoke(Alloc(size), LirEdge(normal), LirEdge(handler)));
      return _module([entry, normal, handler]);
    });
  });

  test('the interpreter refuses an invalid module', () {
    expect(() => LirInterpreter(_module([])), throwsA(isA<LirError>()));
  });
}
