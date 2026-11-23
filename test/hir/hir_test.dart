import 'package:dartc/hir.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  void rejects(String message, HirModule Function() build, [String how = '']) =>
      test('rejects $message $how', () {
        final matcher = throwsA(
          isA<HirError>().having(
            (e) => e.message,
            'message',
            contains(message),
          ),
        );
        expect(() => verifyHir(build()), matcher);
        expect(() => HirInterpreter(build()), matcher);
      });

  HirModule blocks(List<HirBlock> blocks, [HirType? result]) {
    final main = HirFunction('main', const [], result)..define(blocks);
    return HirModule(main, [main]);
  }

  group('structure', () {
    rejects('a function is listed twice', () {
      final main = HirFunction('main', const [])
        ..define([HirBlock()..end(HirReturn())]);
      return HirModule(main, [main, main]);
    });
    rejects('main is not listed', () {
      return HirModule(HirFunction('main', const []), []);
    });
    rejects('main has parameters', () {
      final main = HirFunction('main', [.integer]);
      return HirModule(main, [main]);
    });
    rejects('no blocks', () => blocks([]));
    rejects('a block is listed twice', () {
      final block = HirBlock()..end(HirReturn());
      return blocks([block, block]);
    });
    rejects('entry parameters', () {
      return blocks([
        HirBlock([.integer])..end(HirReturn()),
      ]);
    });
    rejects('no terminator', () => blocks([HirBlock()]));
    rejects('edge leaves the function', () {
      final other = HirBlock()..end(HirReturn());
      return blocks([HirBlock()..end(HirJump(HirEdge(other)))]);
    });
    rejects('edge enters the entry block', () {
      final block = HirBlock();
      block.end(HirJump(HirEdge(block)));
      return blocks([block]);
    });
    rejects('unreachable block', () {
      return blocks([
        HirBlock()..end(HirReturn()),
        HirBlock()..end(HirReturn()),
      ]);
    });
    test('bodies and terminators are supplied once', () {
      final function = HirFunction('f', const []);
      expect(() => function.blocks, throwsStateError);
      final block = HirBlock()..end(HirReturn());
      function.define([block]);
      expect(() => function.define([block]), throwsStateError);
      expect(() => block.end(HirReturn()), throwsStateError);
      expect(() => block.add(HirConst(1)), throwsStateError);
      expect(() => HirConst('text').type, throwsArgumentError);
    });
  });

  group('definitions', () {
    rejects('use of an undefined value', () {
      return body((block) => HirExit(HirConst(1)));
    });
    rejects('use of an undefined value', () {
      final next = HirBlock([.integer])..end(HirReturn());
      final entry = HirBlock()..end(HirJump(HirEdge(next, [HirConst(1)])));
      return blocks([entry, next]);
    });
    rejects('use of an operation without a result', () {
      final callee = HirFunction('f', const [])
        ..define([HirBlock()..end(HirReturn())]);
      return body((block) => HirExit(block.add(HirCall(callee, []))), [callee]);
    });
    rejects('a value is defined twice', () {
      return body((block) {
        final value = block.add(HirConst(1));
        block.add(value);
        return HirReturn();
      });
    });
    rejects('does not dominate', () {
      return body((block) {
        final late = HirConst(1);
        block.add(HirUnary(.negateInt, late));
        block.add(late);
        return HirReturn();
      });
    });
    rejects('does not dominate', () {
      final entry = HirBlock(), left = HirBlock(), right = HirBlock();
      final join = HirBlock();
      final condition = entry.add(HirConst(true));
      entry.end(HirBranch(condition, HirEdge(left), HirEdge(right)));
      final value = left.add(HirConst(1));
      left.end(HirJump(HirEdge(join)));
      right.end(HirJump(HirEdge(join)));
      join.end(HirExit(value));
      return blocks([entry, left, right, join]);
    });
  });

  group('operands', () {
    void operation(
      String message,
      HirInstruction Function(HirValue i, HirValue d, HirValue b) build,
    ) => rejects(message, () {
      return body((block) {
        final i = block.add(HirConst(1)), d = block.add(HirConst(1.5));
        block.add(build(i, d, block.add(HirConst(true))));
        return HirReturn();
      });
    });

    operation('+: expected int', (i, d, _) => HirIntBinary(.add, d, i));
    operation('+: expected int', (i, d, _) => HirIntBinary(.add, i, d));
    operation('+: expected double', (i, d, _) => HirFloatBinary(.add, i, d));
    operation('+: expected double', (i, d, _) => HirFloatBinary(.add, d, i));
    operation('&: expected bool', (i, _, b) => HirBoolBinary(.and, i, b));
    operation('&: expected bool', (i, _, b) => HirBoolBinary(.and, b, i));
    operation('not: expected bool', (i, _, _) => HirUnary(.not, i));
    operation('==: expected int', (i, d, _) => HirCompare(.equal, i, d));
    operation('bool has no <', (_, _, b) => HirCompare(.less, b, b));
    for (final (operator, bad) in [
      (HirIntOperator.divide, 0),
      (HirIntOperator.modulo, 0),
      (HirIntOperator.shiftLeft, -1),
      (HirIntOperator.shiftRight, -1),
      (HirIntOperator.shiftRightUnsigned, -1),
    ]) {
      final message = '${operator.symbol} could throw';
      rejects(message, () {
        return body((block) {
          final left = block.add(HirConst(1)), right = block.add(HirConst(bad));
          block.add(HirIntBinary(operator, left, right));
          return HirReturn();
        });
      });
      rejects(message, () {
        return body((block) {
          final left = block.add(HirConst(1));
          final right = block.add(HirUnary(.negateInt, left));
          block.add(HirIntBinary(operator, left, right));
          return HirReturn();
        });
      }, 'with a variable');
    }
    rejects('unlisted callee', () {
      return body((block) {
        block.add(HirCall(HirFunction('f', const []), []));
        return HirReturn();
      });
    });
    for (final arguments in [0, 1.5]) {
      rejects('call to f', () {
        final entry = HirBlock([.integer])..end(HirReturn());
        final callee = HirFunction('f', [.integer])..define([entry]);
        return body((block) {
          block.add(
            HirCall(callee, [
              if (arguments is double) block.add(HirConst(arguments)),
            ]),
          );
          return HirReturn();
        }, [callee]);
      });
    }
  });

  group('terminators', () {
    rejects('branch condition', () {
      final entry = HirBlock(), left = HirBlock()..end(HirReturn());
      final right = HirBlock()..end(HirReturn());
      final value = entry.add(HirConst(1));
      entry.end(HirBranch(value, HirEdge(left), HirEdge(right)));
      return blocks([entry, left, right]);
    });
    rejects('returns int', () {
      return body((block) => HirReturn(block.add(HirConst(1))));
    });
    rejects('returns null', () {
      return blocks([HirBlock()..end(HirReturn())], .integer);
    });
    rejects('exit code', () {
      return body((block) => HirExit(block.add(HirConst(true))));
    });
    for (final arguments in [0, true]) {
      rejects('edge arguments', () {
        final next = HirBlock([.integer])..end(HirReturn());
        final entry = HirBlock();
        entry.end(
          HirJump(
            HirEdge(next, [
              if (arguments is bool) entry.add(HirConst(arguments)),
            ]),
          ),
        );
        return blocks([entry, next]);
      });
    }
  });

  group('interpreter', () {
    /// The result of an operation, observed through one exit per answer.
    bool holds(HirValue Function(HirBlock block) build) =>
        HirInterpreter(
          body((block) {
            final condition = build(block);
            final yes = block.add(HirConst(1));
            final result = block.add(HirUnary(.intToFloat, yes));
            return _exitIf(block, condition, result);
          }),
        ).run() ==
        1;

    test('operators follow Dart', () {
      for (final a in integers) {
        for (final b in integers) {
          for (final operator in HirIntOperator.values) {
            final expected = integerResult(operator, a, b);
            if (expected == null) continue;
            final module = body((block) {
              final l = block.add(HirConst(a)), r = block.add(HirConst(b));
              return HirExit(block.add(HirIntBinary(operator, l, r)));
            });
            expect(HirInterpreter(module).run(), expected);
          }
        }
      }
      for (final a in doubles) {
        for (final b in doubles) {
          for (final operator in HirFloatOperator.values) {
            final expected = doubleResult(operator, a, b);
            expect(
              holds((block) {
                final l = block.add(HirConst(a)), r = block.add(HirConst(b));
                final found = block.add(HirFloatBinary(operator, l, r));
                return sameDouble(block, found, expected);
              }),
              isTrue,
              reason: '$a ${operator.symbol} $b',
            );
          }
        }
      }
    });

    test('comparisons follow Dart', () {
      for (final List<num> values in [integers, doubles]) {
        for (final a in values) {
          for (final b in values) {
            for (final relation in HirRelation.values) {
              final found = holds((block) {
                final l = block.add(HirConst(a)), r = block.add(HirConst(b));
                return block.add(HirCompare(relation, l, r));
              });
              expect(
                found,
                relationResult(relation, a, b),
                reason: '$a ${relation.symbol} $b',
              );
            }
          }
        }
      }
    });

    test('bool operators follow Dart', () {
      for (final a in [true, false]) {
        HirValue constant(HirBlock block, bool value) =>
            block.add(HirConst(value));
        expect(holds((b) => b.add(HirUnary(.not, constant(b, a)))), !a);
        for (final b in [true, false]) {
          for (final (operator, expected) in [
            (HirBoolOperator.and, a & b),
            (HirBoolOperator.or, a | b),
            (HirBoolOperator.xor, a ^ b),
          ]) {
            final found = holds((block) {
              final l = constant(block, a), r = constant(block, b);
              return block.add(HirBoolBinary(operator, l, r));
            });
            expect(found, expected);
          }
        }
      }
    });

    test('calls and loops pass values', () {
      final module = loopingCalls();
      expect(HirInterpreter(module).run(), 34);
      expect(
        () => HirInterpreter(module, maxSteps: 20).run(),
        throwsStateError,
      );
    });

    test('output keeps its order', () {
      final interpreter = HirInterpreter(
        body((block) {
          block
            ..add(HirPrint('a'))
            ..add(HirPrint(''))
            ..add(HirPrint('b'));
          return HirReturn();
        }),
      );
      expect(interpreter.output, isEmpty);
      interpreter.run();
      expect(interpreter.output, 'a\n\nb\n');
    });

    test('a runaway program is stopped', () {
      final entry = HirBlock(), loop = HirBlock();
      entry.end(HirJump(HirEdge(loop)));
      loop.end(HirJump(HirEdge(loop)));
      expect(
        () => HirInterpreter(blocks([entry, loop]), maxSteps: 100).run(),
        throwsStateError,
      );
    });

    test('unreachable code is an error', () {
      expect(
        () => HirInterpreter(body((_) => HirUnreachable())).run(),
        throwsStateError,
      );
    });

    test('returning is not exiting', () {
      expect(HirInterpreter(body((_) => HirReturn())).run(), isNull);
    });
  });

  test('prints every construct', () {
    final callee = HirFunction('f', [.float], .float);
    final only = HirBlock([.float]);
    only.end(HirReturn(only.parameters.single));
    callee.define([only]);
    final entry = HirBlock(), next = HirBlock([.integer]), last = HirBlock();
    final never = HirBlock()..end(HirUnreachable());
    final i = entry.add(HirConst(-1)), b = entry.add(HirConst(true));
    final d = entry.add(HirUnary(.intToFloat, i));
    entry
      ..add(HirPrint('a\n"'))
      ..add(HirCall(callee, [d]))
      ..add(HirIntBinary(.shiftLeft, i, entry.add(HirConst(2))))
      ..add(HirFloatBinary(.divide, d, d))
      ..add(HirBoolBinary(.xor, b, b))
      ..add(HirCompare(.lessOrEqual, d, d))
      ..end(HirBranch(b, HirEdge(next, [i]), HirEdge(last)));
    next.end(HirExit(next.parameters.single));
    last.end(HirBranch(b, HirEdge(never), HirEdge(next, [i])));
    final main = HirFunction('main', const [])
      ..define([entry, next, last, never]);
    final module = HirModule(main, [main, callee]);
    verifyHir(module);
    expect(printHir(module), '''
void main {
b0():
  v0 = -1
  v1 = true
  v2 = double v0
  print "a\\n\\""
  v3 = f(v2)
  v4 = 2
  v5 = v0 << v4
  v6 = v2 / v2
  v7 = v1 ^ v1
  v8 = v2 <= v2
  branch v1, b1(v0), b2()
b1(int v9):
  exit v9
b2():
  branch v1, b3(), b1(v0)
b3():
  unreachable
}
double f {
b0(double v0):
  return v0
}''');
  });

  test('prints a broken function without failing', () {
    final text = printHir(
      blocks([HirBlock()..add(HirUnary(.not, HirConst(true)))]),
    );
    expect(text, contains('!<undefined>'));
    expect(text, contains('<no terminator>'));
  });
}

/// Exits with 1 if [condition] holds and 0 otherwise; [unused] is ignored.
HirTerminator _exitIf(HirBlock block, HirValue condition, HirValue unused) {
  final yes = HirBlock(), no = HirBlock();
  yes.end(HirExit(yes.add(HirConst(1))));
  no.end(HirExit(no.add(HirConst(0))));
  return HirBranch(condition, HirEdge(yes), HirEdge(no));
}
