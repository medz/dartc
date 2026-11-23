@TestOn('mac-os')
@Tags(['native'])
library;

import 'package:dartc/lir.dart';
import 'package:test/test.dart';

import '../lir/support.dart';
import 'agree.dart';
import 'support.dart';

void main() {
  test('every width is stored and loaded in objects', () async {
    final functions = <LirFunction>[], cases = <Case>[];
    for (final width in Width.values) {
      if (width == .ref) continue;
      // Within reach of an encoded offset, and beyond it.
      for (final offset in [16, 17, 40000]) {
        for (final indexed in [true, false]) {
          final name = '${width.name}.$offset.$indexed';
          functions.add(
            function(name, [.i64, .i64], .i64, (block, p) {
              final size = block.add(ConstInt(50000));
              final object = block.add(Alloc(size));
              final many = [
                for (var i = 0; i < 30; i++) block.add(ConstInt(i)),
              ];
              final LirValue value = switch (width.type) {
                .f64 => block.add(Convert(.intToFloat, p[0])),
                .ptr => block.add(Convert(.intToPtr, p[0])),
                _ => p[0],
              };
              final index = indexed ? p[1] : null;
              block.add(
                Store(width, object, value, offset: offset, index: index),
              );
              final found = block.add(
                Load(width, object, offset: offset, index: index),
              );
              LirValue sum = switch (found.type) {
                .f64 => block.add(Convert(.floatBitsToInt, found)),
                .ptr => block.add(Convert(.ptrToInt, found)),
                _ => found,
              };
              // The bytes around it are untouched.
              for (final near in [-8, 8]) {
                final other = block.add(
                  Load(.u8, object, offset: offset + near, index: index),
                );
                sum = block.add(IntBinary(.add, sum, other));
              }
              for (final value in many) {
                sum = block.add(IntBinary(.add, sum, value));
              }
              return sum;
            }),
          );
          for (final value in [0, -1, 0x1234567890abcdef, -77]) {
            cases.add((function: name, arguments: [value, 8]));
          }
        }
      }
    }
    await agree(functions, cases);
  }, skip: skipExecution);

  test('references survive calls, joins and the stack', () async {
    // Builds a list of n objects and adds up what they hold.
    final pair = LirSignature([.ref, .i64], .ref);
    final cons = function('cons', pair.parameters, .ref, (block, p) {
      final object = block.add(Alloc(block.add(ConstInt(24))));
      block.add(Store(.ref, object, p[0], offset: 8));
      block.add(Store(.i64, object, p[1], offset: 16));
      return object;
    });
    final entry = LirBlock([.i64]), loop = LirBlock([.i64, .ref]);
    final grow = LirBlock(), sum = LirBlock([.ref, .i64]);
    final take = LirBlock(), done = LirBlock();
    final none = entry.add(ConstNull());
    entry.end(Jump(LirEdge(loop, [entry.parameters.single, none])));
    final [n, list] = loop.parameters;
    final zero = loop.add(ConstInt(0));
    loop.end(Branch(n, LirEdge(grow), LirEdge(sum, [list, zero])));
    final longer = grow.add(Call('cons', pair, [list, n]));
    final less = grow.add(IntBinary(.sub, n, grow.add(ConstInt(1))));
    grow.end(Jump(LirEdge(loop, [less, longer])));
    final [rest, total] = sum.parameters;
    final ended = sum.add(Compare(.eq, rest, sum.add(ConstNull())));
    sum.end(Branch(ended, LirEdge(done), LirEdge(take)));
    final value = take.add(Load(.i64, rest, offset: 16));
    final next = take.add(Load(.ref, rest, offset: 8));
    final more = take.add(IntBinary(.add, total, value));
    take.end(Jump(LirEdge(sum, [next, more])));
    done.end(Return(total));
    final build = LirFunction('build', LirSignature([.i64], .i64), [
      entry,
      loop,
      grow,
      sum,
      take,
      done,
    ]);
    // More references alive across a call than there are registers.
    final many = function('many', [.i64], .i64, (block, p) {
      final objects = <LirValue>[block.add(ConstNull())];
      for (var i = 0; i < 40; i++) {
        final value = block.add(IntBinary(.add, p[0], block.add(ConstInt(i))));
        objects.add(block.add(Call('cons', pair, [objects.last, value])));
      }
      LirValue sum = block.add(ConstInt(0));
      for (final (i, object) in objects.indexed.skip(1)) {
        final value = block.add(Load(.i64, object, offset: 16));
        final link = block.add(Load(.ref, object, offset: 8));
        final linked = block.add(Compare(.eq, link, objects[i - 1]));
        sum = block.add(IntBinary(.mul, sum, block.add(ConstInt(3))));
        sum = block.add(IntBinary(.add, sum, value));
        sum = block.add(IntBinary(.add, sum, linked));
      }
      return sum;
    });
    await agree(
      [cons, build, many],
      [
        for (final n in [0, 1, 2, 1000]) (function: 'build', arguments: [n]),
        (function: 'many', arguments: [5]),
      ],
    );
  }, skip: skipExecution);

  test('operands and results that live on the stack', () async {
    final unary = LirSignature([.i64], .i64);
    final id = function('id', [.i64], .i64, (_, p) => p[0]);
    final functions = [id], cases = <Case>[];
    for (final width in <Width>[.i64, .u8, .f64, .f32]) {
      functions.add(
        function('f.${width.name}', [.i64], .i64, (block, p) {
          // Alive across calls, so most of these have no register.
          final objects = [
            for (var i = 0; i < 15; i++)
              block.add(Alloc(block.add(ConstInt(64 + i)))),
          ];
          final indexes = [
            for (var i = 0; i < 15; i++) block.add(ConstInt(8 * (i % 4))),
          ];
          final values = <LirValue>[
            for (var i = 0; i < 15; i++)
              block.add(IntBinary(.add, p[0], block.add(ConstInt(i * 3)))),
          ];
          if (width.type == .f64) {
            for (var i = 0; i < 15; i++) {
              values[i] = block.add(Convert(.intToFloat, values[i]));
            }
          }
          LirValue sum = block.add(Call('id', unary, [p[0]]));
          for (var i = 0; i < 15; i++) {
            block.add(
              Store(width, objects[i], values[i], offset: 8, index: indexes[i]),
            );
          }
          block.add(Call('id', unary, [sum]));
          for (var i = 0; i < 15; i++) {
            final LirValue found = block.add(
              Load(width, objects[i], offset: 8, index: indexes[i]),
            );
            final bits = found.type == .f64
                ? block.add(Convert(.floatBitsToInt, found))
                : found;
            sum = block.add(IntBinary(.mul, sum, block.add(ConstInt(31))));
            sum = block.add(IntBinary(.add, sum, bits));
          }
          // Used again, so they stay alive until here.
          for (var i = 0; i < 15; i++) {
            block.add(Store(.i64, objects[i], indexes[i]));
            final again = block.add(Load(.i64, objects[i]));
            sum = block.add(IntBinary(.xor, sum, again));
            final bits = values[i].type == .f64
                ? block.add(Convert(.floatBitsToInt, values[i]))
                : values[i];
            sum = block.add(IntBinary(.add, sum, bits));
          }
          return sum;
        }),
      );
      for (final value in [0, -1, 1000]) {
        cases.add((function: 'f.${width.name}', arguments: [value]));
      }
    }
    await agree(functions, cases);
  }, skip: skipExecution);

  test('new objects are zero', () async {
    await agree(
      [
        function('f', [.i64], .i64, (block, p) {
          final object = block.add(Alloc(p[0]));
          final word = block.add(Load(.i64, object));
          final link = block.add(Load(.ref, object, offset: 8));
          final empty = block.add(Compare(.eq, link, block.add(ConstNull())));
          return block.add(IntBinary(.sub, word, empty));
        }),
      ],
      [
        for (final size in [16, 17, 5000]) (function: 'f', arguments: [size]),
      ],
    );
  }, skip: skipExecution);

  test('functions are called through tables', () async {
    final unary = LirSignature([.i64], .i64);
    final functions = [
      for (var i = 0; i < 5; i++)
        function('f$i', [.i64], .i64, (block, p) {
          return block.add(IntBinary(.mul, p[0], block.add(ConstInt(i + 2))));
        }),
      function('call', [.i64, .i64], .i64, (block, p) {
        LirValue result = p[1];
        // Two tables, so both need their own addresses.
        for (final name in ['a', 'b']) {
          final table = block.add(SymbolAddress(name));
          final at = block.add(IntBinary(.shl, p[0], block.add(ConstInt(2))));
          final offset = block.add(Load(.i32, table, index: at));
          final callee = block.add(PtrAdd(table, offset));
          result = block.add(CallIndirect(callee, unary, [result]));
        }
        return result;
      }),
    ];
    await agree(
      functions,
      [
        for (var i = 0; i < 3; i++) (function: 'call', arguments: [i, 7]),
      ],
      tables: [
        LirTable('a', ['f0', 'f4', 'f2']),
        LirTable('b', ['f1', 'f1', 'f3']),
      ],
      data: [
        LirData('odd', [1, 2, 3]),
      ],
    );
  }, skip: skipExecution);
}
