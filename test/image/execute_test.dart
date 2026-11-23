@TestOn('mac-os')
@Tags(['native'])
library;

import 'package:dartc/lir.dart';
import 'package:test/test.dart';

import '../emit/random_lir.dart';
import '../lir/support.dart';
import 'agree.dart';
import 'support.dart';

const _min = -0x8000000000000000, _max = 0x7fffffffffffffff;
void main() {
  test('a wrong result is reported with its case number', () async {
    final identity = function('id', [.i64], .i64, (_, p) => p[0]);
    final cases = [
      for (var i = 0; i < 5; i++) (function: 'id', arguments: [i]),
    ];
    expect(await execute(program([identity], cases, [0, 1, 2, 3, 4])), 0);
    for (var wrong = 0; wrong < 5; wrong++) {
      final expected = [0, 1, 2, 3, 4];
      // Only the top bit differs, so all 64 bits must be compared.
      expected[wrong] ^= _min;
      expect(await execute(program([identity], cases, expected)), wrong + 1);
    }
  }, skip: skipExecution);

  test('every integer operation and comparison', () async {
    const values = [0, 1, -1, 2, 7, -7, 63, _max, _min, 0x123456789];
    final functions = <LirFunction>[], cases = <Case>[];
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
    await agree(functions, cases);
  }, skip: skipExecution);

  test('every floating-point operation', () async {
    const values = [
      0.0,
      -0.0,
      1.0,
      -2.5,
      0.1,
      1e308,
      5e-324,
      9007199254740993.0,
      double.infinity,
      double.negativeInfinity,
      double.nan,
    ];
    final functions = <LirFunction>[], cases = <Case>[];
    // Results are compared by their bits, except that all NaNs are equal.
    LirValue bits(LirBlock block, LirValue value) {
      final word = block.add(Convert(.floatBitsToInt, value));
      final known = block.add(Compare(.eq, value, value));
      return block.add(IntBinary(.mul, word, known));
    }

    void pair(
      String name,
      LirValue Function(LirBlock b, LirValue x, LirValue y) build,
    ) {
      functions.add(
        function(name, [.f64, .f64], .i64, (b, p) => build(b, p[0], p[1])),
      );
      for (final x in values) {
        for (final y in values) {
          cases.add((function: name, arguments: [x, y]));
        }
      }
    }

    for (final op in FloatOp.values) {
      pair('op.${op.name}', (block, x, y) {
        return bits(block, block.add(FloatBinary(op, x, y)));
      });
    }
    for (final op in FloatUnaryOp.values) {
      pair('op.${op.name}', (block, x, _) {
        return bits(block, block.add(FloatUnary(op, x)));
      });
    }
    for (final relation in Relation.values.where((r) => !r.isUnsigned)) {
      pair('is.${relation.name}', (block, x, y) {
        return block.add(Compare(relation, x, y));
      });
    }
    functions.add(
      function('from', [.i64], .i64, (block, p) {
        return bits(block, block.add(Convert(.intToFloat, p[0])));
      }),
    );
    functions.add(
      function('raw', [.i64], .i64, (block, p) {
        final value = block.add(Convert(.intBitsToFloat, p[0]));
        return block.add(Convert(.floatBitsToInt, value));
      }),
    );
    functions.add(
      function('to', [.f64], .i64, (block, p) {
        return block.add(Convert(.floatToInt, p[0]));
      }),
    );
    for (final value in [0, 1, -1, _max, _min, 9007199254740993]) {
      cases.add((function: 'from', arguments: [value]));
      cases.add((function: 'raw', arguments: [value]));
    }
    for (final value in [0.0, -0.9, 1.9, -2.5, 1e18, -9223372036854775808.0]) {
      cases.add((function: 'to', arguments: [value]));
    }
    await agree(functions, cases);
  }, skip: skipExecution);

  test('floating-point arguments and results of every kind', () async {
    // Both banks overflow to the stack, interleaved.
    final types = [
      for (var i = 0; i < 24; i++) i.isEven ? LirType.i64 : LirType.f64,
    ];
    final mixed = function('mixed', types, .f64, (block, p) {
      LirValue sum = block.add(ConstFloat(0));
      for (final (i, value) in p.indexed) {
        final term = value.type == .i64
            ? block.add(Convert(.intToFloat, value))
            : value;
        final weight = block.add(ConstFloat(i + 0.5));
        sum = block.add(FloatBinary(.mul, sum, block.add(ConstFloat(1.25))));
        sum = block.add(
          FloatBinary(.add, sum, block.add(FloatBinary(.mul, term, weight))),
        );
      }
      return sum;
    });
    final forward = function('forward', types, .i64, (block, p) {
      final words = p.where((v) => v.type == .i64).toList().reversed.toList();
      final floats = p.where((v) => v.type == .f64).toList().reversed.toList();
      final result = block.add(
        Call('mixed', mixed.signature, [
          for (var i = 0; i < 12; i++) ...[words[i], floats[i]],
        ]),
      );
      // The arguments must survive the call.
      LirValue sum = result;
      for (final value in floats) {
        sum = block.add(FloatBinary(.add, sum, value));
      }
      LirValue bits = block.add(Convert(.floatBitsToInt, sum));
      for (final value in words) {
        bits = block.add(IntBinary(.xor, bits, value));
      }
      return bits;
    });
    await agree(
      [mixed, forward],
      [
        (
          function: 'forward',
          arguments: [for (var i = 0; i < 24; i++) i.isEven ? i * 7 : i / 3],
        ),
      ],
    );
  }, skip: skipExecution);

  test('system functions taking doubles', () async {
    final pow = LirSignature([.f64, .f64], .f64);
    final block = LirBlock();
    final result = block.add(
      Call('pow', pow, [block.add(ConstFloat(1.5)), block.add(ConstFloat(8))]),
    );
    block.end(Return(block.add(Convert(.floatToInt, result))));
    final module = LirModule(
      functions: [
        LirFunction('main', LirSignature([], .i64), [block]),
      ],
      externals: [LirExternal('pow', pow)],
    );
    expect(await execute(module), 25);
  }, skip: skipExecution);

  test('every constant shape', () async {
    final values = [
      for (final high in [0, 1, 0xffff])
        for (final low in [0, 1, 0xffff, 0x8000])
          for (final middle in [0, 0xffff0000, 0x1234ffff0000, 0xffffffff0000])
            high << 48 | middle | low,
    ];
    await agree(
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

    await agree(
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
    await agree(
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
    await agree(functions, [
      for (final name in operations.keys)
        for (final a in [0, 7, -7, _max, _min])
          (function: name, arguments: [a, 0x7654321 - a]),
    ]);
  }, skip: skipExecution);

  test('loads of every width from constant data', () async {
    // Every byte differs from its neighbors, and some are negative.
    final bytes = [for (var i = 0; i < 70000; i++) (i * 167 + i ~/ 256) & 0xff];
    final data = [
      LirData('small', [0xff]),
      LirData('empty', []),
      LirData('big', bytes),
    ];
    final functions = <LirFunction>[], cases = <Case>[];
    // Near and far, aligned and not, forward and backward.
    for (final offset in [0, 1, 8, 32760, 32761, 65536, -16]) {
      for (final width in Width.values) {
        if (width == .ref) continue;
        for (final indexed in [true, false]) {
          final name = '${width.name}.$offset.$indexed';
          functions.add(
            function(name, [.i64], .i64, (block, p) {
              final start = block.add(SymbolAddress('big'));
              final base = block.add(PtrAdd(start, block.add(ConstInt(16))));
              // With many values alive, the operands come from the stack.
              final many = [
                for (var i = 0; i < 30; i++) block.add(ConstInt(i)),
              ];
              final value = block.add(
                Load(width, base, offset: offset, index: indexed ? p[0] : null),
              );
              LirValue sum = switch (value.type) {
                .f64 => block.add(Convert(.floatBitsToInt, value)),
                .ptr => block.add(Convert(.ptrToInt, value)),
                _ => value,
              };
              // Any NaN may stand for another.
              if (value.type == .f64) {
                final known = block.add(Compare(.eq, value, value));
                sum = block.add(IntBinary(.mul, sum, known));
              }
              for (final (i, value) in many.indexed) {
                sum = block.add(IntBinary(.add, sum, value));
                if (i == 15) {
                  final again = block.add(Load(.u8, base, index: p[0]));
                  sum = block.add(IntBinary(.add, sum, again));
                }
              }
              return sum;
            }),
          );
          for (final index in [0, 3, 1000]) {
            cases.add((function: name, arguments: [index]));
          }
        }
      }
    }
    functions.add(
      function('first', [], .i64, (block, _) {
        final address = block.add(SymbolAddress('small'));
        return block.add(Load(.i8, address));
      }),
    );
    cases.add((function: 'first', arguments: []));
    await agree(functions, cases, data: data);
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
    await agree(
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
      final functions = <LirFunction>[], cases = <Case>[];
      for (var seed = group * 25; seed < (group + 1) * 25; seed++) {
        final random = RandomLir(seed, prefix: 'r');
        for (final made in random.functions()) {
          functions.add(made);
          if (made.signature.result != .i64) continue;
          for (var i = 0; i < 4; i++) {
            final arguments = [
              ...made.signature.parameters.map(random.argument),
            ];
            cases.add((function: made.name, arguments: arguments));
          }
        }
      }
      await agree(functions, cases);
    }, skip: skipExecution);
  }
}
