@TestOn('mac-os')
@Tags(['native'])
library;

import 'package:dartc/lir.dart';
import 'package:test/test.dart';

import '../emit/random_lir.dart';
import '../lir/support.dart';
import 'support.dart';

typedef _Case = ({String function, List<int> arguments});

const _min = -0x8000000000000000, _max = 0x7fffffffffffffff;
const _limit = 250;

/// A program returning the 1-based number of the first case that differs from
/// [expected], or 0.
LirModule _program(
  List<LirFunction> functions,
  List<_Case> cases,
  List<int> expected,
) {
  final signatures = {for (final f in functions) f.name: f.signature};
  var block = LirBlock();
  final blocks = [block];
  for (final (i, (:function, :arguments)) in cases.indexed) {
    final call = block.add(
      Call(function, signatures[function]!, [
        for (final value in arguments) block.add(ConstInt(value)),
      ]),
    );
    final same = block.add(
      Compare(.eq, call, block.add(ConstInt(expected[i]))),
    );
    final next = LirBlock(), failed = LirBlock();
    block.end(Branch(same, LirEdge(next), LirEdge(failed)));
    failed.end(Return(failed.add(ConstInt(i + 1))));
    blocks.addAll([failed, next]);
    block = next;
  }
  block.end(Return(block.add(ConstInt(0))));
  return LirModule(
    functions: [
      ...functions,
      LirFunction('main', LirSignature([], .i64), blocks),
    ],
  );
}

/// Checks that machine code agrees with the interpreter on every case.
Future<void> _agree(List<LirFunction> functions, List<_Case> cases) async {
  for (var at = 0; at < cases.length; at += _limit) {
    final part = cases.skip(at).take(_limit).toList();
    final interpreter = LirInterpreter(LirModule(functions: functions));
    final expected = [
      for (final (:function, :arguments) in part)
        interpreter.call(function, arguments) as int,
    ];
    final code = await execute(_program(functions, part, expected));
    expect(
      code,
      0,
      reason: code > 0 ? 'differs: ${part[code - 1]}' : 'signal ${-code}',
    );
  }
}

void main() {
  test('a wrong result is reported with its case number', () async {
    final identity = function('id', [.i64], .i64, (_, p) => p[0]);
    final cases = [
      for (var i = 0; i < 5; i++) (function: 'id', arguments: [i]),
    ];
    expect(await execute(_program([identity], cases, [0, 1, 2, 3, 4])), 0);
    for (var wrong = 0; wrong < 5; wrong++) {
      final expected = [0, 1, 2, 3, 4];
      // Only the top bit differs, so all 64 bits must be compared.
      expected[wrong] ^= _min;
      expect(await execute(_program([identity], cases, expected)), wrong + 1);
    }
  }, skip: skipExecution);

  test('every integer operation and comparison', () async {
    const values = [0, 1, -1, 2, 7, -7, 63, _max, _min, 0x123456789];
    final functions = <LirFunction>[], cases = <_Case>[];
    void operation(
      String name,
      LirInstruction Function(LirValue a, LirValue b) build,
      bool Function(int a, int b) allowed,
    ) {
      functions.add(
        function(name, [.i64, .i64], .i64, (b, p) => b.add(build(p[0], p[1]))),
      );
      for (final a in values) {
        for (final b in values.where((b) => allowed(a, b))) {
          cases.add((function: name, arguments: [a, b]));
        }
      }
    }

    for (final op in IntOp.values) {
      operation('op.${op.name}', (a, b) => IntBinary(op, a, b), (_, b) {
        return switch (op) {
          .div || .rem => b != 0,
          .shl || .sar || .shr => b >= 0 && b < 64,
          _ => true,
        };
      });
    }
    for (final relation in Relation.values) {
      operation(
        'is.${relation.name}',
        (a, b) => Compare(relation, a, b),
        (_, _) => true,
      );
    }
    functions.add(
      function('address', [.i64, .i64], .i64, (block, p) {
        final base = block.add(Convert(.intToPtr, p[0]));
        final sum = block.add(PtrAdd(base, p[1]));
        final differs = block.add(Compare(.ne, sum, base));
        final bits = block.add(Convert(.ptrToInt, sum));
        return block.add(IntBinary(.sub, bits, differs));
      }),
    );
    for (final a in values) {
      cases.add((function: 'address', arguments: [a, 5]));
      cases.add((function: 'address', arguments: [a, 0]));
    }
    await _agree(functions, cases);
  }, skip: skipExecution);

  test('every constant shape', () async {
    final values = [
      for (final high in [0, 1, 0xffff])
        for (final low in [0, 1, 0xffff, 0x8000])
          for (final middle in [0, 0xffff0000, 0x1234ffff0000, 0xffffffff0000])
            high << 48 | middle | low,
    ];
    await _agree(
      [
        for (final (i, value) in values.indexed)
          function('c$i', [], .i64, (block, _) => block.add(ConstInt(value))),
      ],
      [for (final i in values.indexed) (function: 'c${i.$1}', arguments: [])],
    );
  }, skip: skipExecution);

  test('recursion and mutual calls through addresses', () async {
    final unary = LirSignature([.i64], .i64);
    LirFunction recursive(String name, String other, bool indirect) {
      final entry = LirBlock([.i64]);
      final base = LirBlock(), more = LirBlock();
      final n = entry.parameters.single;
      final two = entry.add(ConstInt(2));
      final small = entry.add(Compare(.lt, n, two));
      entry.end(Branch(small, LirEdge(base), LirEdge(more)));
      base.end(Return(n));
      final one = more.add(ConstInt(1));
      final a = [more.add(IntBinary(.sub, n, one))];
      final b = [more.add(IntBinary(.sub, n, two))];
      final first = more.add(Call(name, unary, a));
      final second = more.add(
        indirect
            ? CallIndirect(more.add(SymbolAddress(other)), unary, b)
            : Call(other, unary, b),
      );
      more.end(Return(more.add(IntBinary(.add, first, second))));
      return LirFunction(name, unary, [entry, base, more]);
    }

    await _agree(
      [recursive('f', 'g', true), recursive('g', 'f', false)],
      [
        for (final n in [0, 1, 2, 10, 20]) (function: 'f', arguments: [n]),
      ],
    );
  }, skip: skipExecution);

  test('stack arguments in both directions', () async {
    final many = List.filled(13, LirType.i64);
    final weigh = function('weigh', many, .i64, (block, p) {
      LirValue sum = block.add(ConstInt(0));
      for (final (i, value) in p.indexed) {
        final factor = block.add(ConstInt(3 * i + 1));
        final term = block.add(IntBinary(.mul, value, factor));
        sum = block.add(IntBinary(.add, sum, term));
      }
      return sum;
    });
    // Forwards its own stack arguments in reverse, by address.
    final reverse = function('reverse', many, .i64, (block, p) {
      final address = block.add(SymbolAddress('weigh'));
      return block.add(CallIndirect(address, weigh.signature, p.reversed));
    });
    final arguments = [for (var i = 0; i < 13; i++) i * i - 5];
    await _agree(
      [weigh, reverse],
      [
        (function: 'weigh', arguments: arguments),
        (function: 'reverse', arguments: arguments),
      ],
    );
  }, skip: skipExecution);

  test('operands and results that live on the stack', () async {
    // Forty values alive across a call cannot all keep registers.
    final functions = <LirFunction>[
      function('id', [.i64], .i64, (_, p) => p[0]),
    ];
    final operations = <String, LirInstruction Function(LirValue, LirValue)>{
      for (final op in IntOp.values) op.name: (a, b) => IntBinary(op, a, b),
      for (final relation in Relation.values)
        'is.${relation.name}': (a, b) => Compare(relation, a, b),
    };
    operations.forEach((name, build) {
      functions.add(
        function(name, [.i64, .i64], .i64, (block, p) {
          final small = block.add(ConstInt(63)), one = block.add(ConstInt(1));
          final left = <LirValue>[], right = <LirValue>[];
          for (var i = 0; i < 20; i++) {
            final salt = block.add(ConstInt(i * 0x1234567 - 99));
            left.add(block.add(IntBinary(.xor, p[0], salt)));
            // Nonzero and below 64, so every operation accepts it.
            final odd = block.add(IntBinary(.add, p[1], salt));
            final low = block.add(IntBinary(.and, odd, small));
            right.add(block.add(IntBinary(.or, low, one)));
          }
          final id = LirSignature([.i64], .i64);
          block.add(Call('id', id, [p[0]]));
          final results = [
            for (final (i, value) in left.indexed)
              block.add(build(value, right[19 - i])),
          ];
          var sum = block.add(Call('id', id, [p[1]])) as LirValue;
          for (final value in [...results, ...left, ...right]) {
            final mixed = block.add(
              IntBinary(.mul, sum, block.add(ConstInt(31))),
            );
            sum = block.add(IntBinary(.add, mixed, value));
          }
          return sum;
        }),
      );
    });
    await _agree(functions, [
      for (final name in operations.keys)
        for (final a in [0, 7, -7, _max, _min])
          (function: name, arguments: [a, 0x7654321 - a]),
    ]);
  }, skip: skipExecution);

  test('frames beyond the reach of load and store offsets', () async {
    // 6000 values alive across a call need about 48 KB of spills.
    final wide = function('wide', [.i64], .i64, (block, p) {
      final values = <LirValue>[];
      for (var i = 0; i < 6000; i++) {
        final constant = block.add(ConstInt(i * 7919));
        values.add(block.add(IntBinary(.xor, p[0], constant)));
      }
      var sum = block.add(Call('id', LirSignature([.i64], .i64), [p[0]]));
      for (final value in values) {
        final mixed = block.add(IntBinary(.mul, sum, values.last));
        block.add(IntBinary(.rem, value, block.add(ConstInt(7))));
        sum = block.add(
          Call('add', LirSignature([.i64, .i64], .i64), [mixed, value]),
        );
      }
      return sum;
    });
    await _agree(
      [
        wide,
        function('id', [.i64], .i64, (_, p) => p[0]),
        function('add', [.i64, .i64], .i64, (block, p) {
          return block.add(IntBinary(.add, p[0], p[1]));
        }),
      ],
      [
        for (final n in [0, 1, -1, _max]) (function: 'wide', arguments: [n]),
      ],
    );
  }, skip: skipExecution);

  for (var group = 0; group < 8; group++) {
    test('random programs, group $group', () async {
      final functions = <LirFunction>[], cases = <_Case>[];
      for (var seed = group * 25; seed < (group + 1) * 25; seed++) {
        final random = RandomLir(seed, prefix: 'r');
        for (final made in random.functions()) {
          functions.add(made);
          for (var i = 0; i < 4; i++) {
            final arguments = [
              for (final _ in made.signature.parameters) random.integer(),
            ];
            cases.add((function: made.name, arguments: arguments));
          }
        }
      }
      await _agree(functions, cases);
    }, skip: skipExecution);
  }
}
